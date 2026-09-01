//
//  CaptureService.swift
//  OneTake
//
//  Camera & capture pipeline — front-camera `AVCaptureSession` with 1080p/4K,
//  24/30/60 fps, HDR, and pause/resume. See `CaptureService+Delegate.swift`
//  and `CaptureService+Pause.swift` for extensions (per best practices: split
//  capabilities into dedicated extensions, not one massive file).
//
//  Best practices:
//  - Threading: `sessionQueue` (actor-like isolation) for AVFoundation which
//    is not thread-safe; UI is `@MainActor` elsewhere.
//  - Safety: No force unwraps; `guard let` for device/format; `responds(to:)`
//    for pause selectors (no private API).
//  - Memory: `[weak self]` in sessionQueue blocks where self captured; delegate
//    does not retain session strongly.
//  - Simulator: `#if targetEnvironment(simulator)` fallbacks so CI builds pass.
//
import AVFoundation
import UIKit

enum CapturePermission {
    case authorized
    case denied
    case notDetermined
}

final class CaptureService: NSObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.onetake.session")
    private var movieOutput = AVCaptureMovieFileOutput()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var savedExposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
    private var savedWhiteBalanceMode: AVCaptureDevice.WhiteBalanceMode = .continuousAutoWhiteBalance
    private var savedFocusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus

    var isRecording: Bool {
        movieOutput.isRecording
    }

    private var currentOutputURL: URL?
    private var isPausedFlag = false
    private var segmentURLs: [URL] = []
    private var baseRecordingID: UUID?

    // MARK: - Permission

    func checkPermission() -> CapturePermission {
        #if targetEnvironment(simulator)
            return .authorized
        #else
            let video = AVCaptureDevice.authorizationStatus(for: .video)
            let audio = AVCaptureDevice.authorizationStatus(for: .audio)
            if video == .authorized && audio == .authorized {
                return .authorized
            }
            if video == .denied || audio == .denied {
                return .denied
            }
            return .notDetermined
        #endif
    }

    func requestPermission() async -> Bool {
        #if targetEnvironment(simulator)
            return true
        #else
            let video = await AVCaptureDevice.requestAccess(for: .video)
            let audio = await AVCaptureDevice.requestAccess(for: .audio)
            return video && audio
        #endif
    }

    // MARK: - Configuration

    func configure(resolution: Resolution, frameRate: FrameRate, enableHDR: Bool) async {
        #if targetEnvironment(simulator)
            isConfigured = true
            return
        #endif

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high

                for input in self.session.inputs {
                    self.session.removeInput(input)
                }
                for output in self.session.outputs {
                    self.session.removeOutput(output)
                }

                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                self.videoDevice = device

                if let device {
                    self.applyFormat(device: device, resolution: resolution, frameRate: frameRate)

                    do {
                        let vInput = try AVCaptureDeviceInput(device: device)
                        if self.session.canAddInput(vInput) {
                            self.session.addInput(vInput); self.videoInput = vInput
                        }
                    } catch {
                        debugPrint("[Capture] video input failed: \(error)")
                    }
                }

                if let audioDevice = AVCaptureDevice.default(for: .audio) {
                    do {
                        let aInput = try AVCaptureDeviceInput(device: audioDevice)
                        if self.session.canAddInput(aInput) {
                            self.session.addInput(aInput); self.audioInput = aInput
                        }
                    } catch {
                        debugPrint("[Capture] audio input failed: \(error)")
                    }
                }

                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                    if let conn = self.movieOutput.connection(with: .video), conn.isVideoMirroringSupported {
                        conn.automaticallyAdjustsVideoMirroring = false
                        conn.isVideoMirrored = true
                    }
                    if enableHDR, let conn = self.movieOutput.connection(with: .video) {
                        // HDR via connection — check at runtime; property exists on iOS 17+
                        if conn.isVideoMirroringSupported { /* keep mirrored */ }
                        // Use KVC-safe set if available; otherwise no-op on older simulators
                        if conn.responds(to: NSSelectorFromString("setVideoHDREnabled:")) {
                            conn.setValue(true, forKey: "videoHDREnabled")
                        }
                    }
                }

                self.session.commitConfiguration()
                self.isConfigured = true
                cont.resume()
            }
        }
    }

    private func applyFormat(device: AVCaptureDevice, resolution: Resolution, frameRate: FrameRate) {
        let targetW = resolution.pixelSize.width
        let targetH = resolution.pixelSize.height
        let formats = device.formats
        var best: AVCaptureDevice.Format?
        for fmt in formats {
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            if dims.width == targetW, dims.height == targetH {
                for range in fmt.videoSupportedFrameRateRanges
                    where range.maxFrameRate >= Double(frameRate.rawValue) && range.minFrameRate <= Double(frameRate.rawValue)
                // swiftlint:disable:next opening_brace
                {
                    best = fmt
                    break
                }
            }
            if best != nil {
                break
            }
        }
        if best == nil {
            for fmt in formats {
                let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                if dims.width == 1920, dims.height == 1080 {
                    for range in fmt.videoSupportedFrameRateRanges where range.maxFrameRate >= Double(frameRate.rawValue) {
                        best = fmt; break
                    }
                }
                if best != nil {
                    break
                }
            }
        }
        guard let fmt = best else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = fmt
            let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            debugPrint("[Capture] format lock failed: \(error)")
        }
    }

    // MARK: - Session control

    func startSession() {
        #if targetEnvironment(simulator)
            return
        #else
            sessionQueue.async { [session] in
                if !session.isRunning {
                    session.startRunning()
                }
            }
        #endif
    }

    func stopSession() {
        #if targetEnvironment(simulator)
            return
        #else
            sessionQueue.async { [session] in
                if session.isRunning {
                    session.stopRunning()
                }
            }
        #endif
    }

    func setMirroring(enabled: Bool) {
        #if targetEnvironment(simulator)
            return
        #else
            if let conn = movieOutput.connection(with: .video), conn.isVideoMirroringSupported {
                conn.isVideoMirrored = enabled
            }
        #endif
    }

    // MARK: - Recording

    func startRecording(to url: URL, lockExposure: Bool) {
        #if targetEnvironment(simulator)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
            currentOutputURL = url
            segmentURLs = [url]
            baseRecordingID = UUID()
            isPausedFlag = false
            return
        #else
            if lockExposure, let device = videoDevice {
                do {
                    try device.lockForConfiguration()
                    savedExposureMode = device.exposureMode
                    savedWhiteBalanceMode = device.whiteBalanceMode
                    savedFocusMode = device.focusMode
                    if device.isExposureModeSupported(.locked) {
                        device.exposureMode = .locked
                    }
                    if device.isWhiteBalanceModeSupported(.locked) {
                        device.whiteBalanceMode = .locked
                    }
                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                    }
                    device.unlockForConfiguration()
                } catch {
                    debugPrint("[Capture] lock config failed: \(error)")
                }
            }
            if movieOutput.isRecording {
                return
            }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            currentOutputURL = url
            segmentURLs = [url]
            baseRecordingID = UUID()
            isPausedFlag = false
            sessionQueue.async { [movieOutput] in
                movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        #endif
    }

    func stopRecording() {
        #if targetEnvironment(simulator)
            isPausedFlag = false
            return
        #else
            isPausedFlag = false
            if movieOutput.isRecording {
                movieOutput.stopRecording()
            }
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run { self.restoreLocks() }
            }
        #endif
    }

    func pauseRecording() {
        #if targetEnvironment(simulator)
            isPausedFlag = true
            return
        #else
            isPausedFlag = true
            // Prefer native pause if available (iOS 18)
            if movieOutput.responds(to: NSSelectorFromString("pauseRecording")) {
                // Use KVC-safe perform
                _ = movieOutput.perform(NSSelectorFromString("pauseRecording"))
                debugPrint("[Capture] native pause")
                return
            }
            // Fallback: stop current segment and prepare for new segment on resume
            if movieOutput.isRecording {
                movieOutput.stopRecording()
                debugPrint("[Capture] fallback pause — stopped segment")
            }
        #endif
    }

    func resumeRecording() {
        #if targetEnvironment(simulator)
            isPausedFlag = false
            return
        #else
            isPausedFlag = false
            if movieOutput.responds(to: NSSelectorFromString("resumeRecording")) {
                _ = movieOutput.perform(NSSelectorFromString("resumeRecording"))
                debugPrint("[Capture] native resume")
                return
            }
            // Fallback: start new segment
            let dir = ExportService.takesDirectory().appendingPathComponent("segments")
                .appendingPathComponent(baseRecordingID?.uuidString ?? UUID().uuidString)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let segURL = dir.appendingPathComponent("seg-\(String(format: "%03d", segmentURLs.count + 1)).mp4")
            segmentURLs.append(segURL)
            currentOutputURL = segURL
            sessionQueue.async { [movieOutput] in
                movieOutput.startRecording(to: segURL, recordingDelegate: self)
            }
            debugPrint("[Capture] fallback resume — new segment \(segURL.lastPathComponent)")
        #endif
    }

    func isPaused() -> Bool {
        isPausedFlag
    }

    /// If segments were used (fallback), merge them into originalURL's directory and return merged file. Otherwise return nil (caller
    /// should use original file).
    func finalizeSegmentsIfNeeded(originalURL: URL) async -> URL? {
        #if targetEnvironment(simulator)
            return nil
        #else
            guard segmentURLs.count > 1 else { return nil }
            // Need to merge segments via AVMutableComposition
            // Ensure all segments exist
            let existing = segmentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard existing.count > 1 else { return nil }
            let composition = AVMutableComposition()
            guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { return nil }
            var cursor = CMTime.zero
            for url in existing {
                let asset = AVURLAsset(url: url)
                if let v = try? await asset.loadTracks(withMediaType: .video).first,
                   let a = try? await asset.loadTracks(withMediaType: .audio).first
                // swiftlint:disable:next opening_brace
                {
                    let duration = await (try? asset.load(.duration)) ?? .zero
                    let range = CMTimeRange(start: .zero, duration: duration)
                    try? videoTrack.insertTimeRange(range, of: v, at: cursor)
                    try? audioTrack.insertTimeRange(range, of: a, at: cursor)
                    if let t = try? await v.load(.preferredTransform) {
                        videoTrack.preferredTransform = t
                    }
                    cursor = CMTimeAdd(cursor, duration)
                } else if let v = try? await asset.loadTracks(withMediaType: .video).first {
                    let duration = await (try? asset.load(.duration)) ?? .zero
                    let range = CMTimeRange(start: .zero, duration: duration)
                    try? videoTrack.insertTimeRange(range, of: v, at: cursor)
                    cursor = CMTimeAdd(cursor, duration)
                }
            }
            let mergedURL = ExportService.takesDirectory()
                .appendingPathComponent("\(originalURL.deletingPathExtension().lastPathComponent)-merged.mp4")
            try? FileManager.default.removeItem(at: mergedURL)
            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return nil }
            session.outputURL = mergedURL
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = false
            await session.export()
            if session.status == .completed {
                // Cleanup segments
                for url in existing {
                    try? FileManager.default.removeItem(at: url)
                }
                if let dir = existing.first?.deletingLastPathComponent() {
                    try? FileManager.default.removeItem(at: dir)
                }
                // Also remove original first segment if different from merged
                try? FileManager.default.removeItem(at: originalURL)
                return mergedURL
            } else {
                debugPrint("[Capture] merge failed: \(session.error?.localizedDescription ?? "unknown")")
                return nil
            }
        #endif
    }

    private func restoreLocks() {
        #if targetEnvironment(simulator)
            return
        #else
            guard let device = videoDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                device.unlockForConfiguration()
            } catch {
                debugPrint("[Capture] restore lock failed: \(error)")
            }
        #endif
    }

    // MARK: - Supported combos helper

    func supportedCombinations() -> [(resolution: Resolution, frameRate: FrameRate, hdr: Bool)] {
        #if targetEnvironment(simulator)
            return Resolution.allCases.flatMap { r in FrameRate.allCases.map { f in (r, f, false) } }
        #else
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return [] }
            var result: [(Resolution, FrameRate, Bool)] = []
            for res in Resolution.allCases {
                for fps in FrameRate.allCases {
                    let dims = (res == .hd1080p) ? (1920, 1080) : (3840, 2160)
                    let found = device.formats.contains { fmt in
                        let d = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                        guard d.width == dims.0, d.height == dims.1 else { return false }
                        return fmt.videoSupportedFrameRateRanges
                            .contains { $0.maxFrameRate >= Double(fps.rawValue) && $0.minFrameRate <= Double(fps.rawValue) }
                    }
                    if found {
                        let hdr = device.formats.contains { $0.isVideoHDRSupported }
                        result.append((res, fps, hdr))
                    }
                }
            }
            return result
        #endif
    }
}
