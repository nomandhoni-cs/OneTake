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
//    for pause selectors (no private API). Missing hardware (no camera/mic)
//    degrades gracefully — inputs are simply skipped, never force-unwrapped.
//  - Memory: `[weak self]` in sessionQueue blocks where self captured; delegate
//    does not retain session strongly.
//  - Production: 100% native AVFoundation on every target, no simulator mocks —
//    without camera hardware the session runs empty and recording surfaces an
//    error through the delegate instead of fabricating files.
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
        let video = AVCaptureDevice.authorizationStatus(for: .video)
        let audio = AVCaptureDevice.authorizationStatus(for: .audio)
        if video == .authorized && audio == .authorized {
            return .authorized
        }
        if video == .denied || audio == .denied {
            return .denied
        }
        return .notDetermined
    }

    func requestPermission() async -> Bool {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        let audio = await AVCaptureDevice.requestAccess(for: .audio)
        return video && audio
    }

    // MARK: - Configuration

    func configure(resolution: Resolution, frameRate: FrameRate, enableHDR: Bool) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                // Stays `.high` here on purpose. Assigning `device.activeFormat`
                // below flips the session to `.inputPriority` on its own
                // ("when a client sets the active format on a device, the
                // associated session's sessionPreset automatically changes to
                // AVCaptureSessionPresetInputPriority" — AVCaptureSession.h),
                // which is what lets a hand-picked 4K format survive. Pinning
                // `.inputPriority` up front instead would strand any session
                // that never reaches `applyFormat` — no matching format, or no
                // camera at all, as on the simulator — with no preset and no
                // inputs.
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
                    do {
                        let vInput = try AVCaptureDeviceInput(device: device)
                        if self.session.canAddInput(vInput) {
                            self.session.addInput(vInput); self.videoInput = vInput
                        }
                    } catch {
                        debugPrint("[Capture] video input failed: \(error)")
                    }

                    // AFTER `addInput`, never before: adding an input reconfigures the
                    // device, so both the format and the frame-rate lock only survive
                    // when applied once the input is already attached.
                    if !self.applyFormat(device: device, resolution: resolution, frameRate: frameRate) {
                        // Nothing matched, so `activeFormat` was never assigned and the
                        // session is still on `.high` — a working fallback, not a stall.
                        debugPrint("[Capture] no format for \(resolution.rawValue)@\(frameRate.rawValue) — staying on .high")
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
                    if enableHDR, let device = self.videoDevice, device.activeFormat.isVideoHDRSupported {
                        // Public HDR toggle on device (iOS 8+, not connection KVC)
                        do {
                            try device.lockForConfiguration()
                            device.automaticallyAdjustsVideoHDREnabled = false
                            device.isVideoHDREnabled = true
                            device.unlockForConfiguration()
                        } catch {
                            debugPrint("[Capture] HDR enable failed: \(error)")
                        }
                    }
                }

                self.session.commitConfiguration()
                self.isConfigured = true
                cont.resume()
            }
        }
    }

    /// Applies the requested capture format + frame-rate lock to `device`.
    /// Returns false when no format matched, so the caller can hand format
    /// selection back to the session instead of leaving it on a stale default.
    /// MUST be called after the device's input is added to the session.
    @discardableResult
    private func applyFormat(device: AVCaptureDevice, resolution: Resolution, frameRate: FrameRate) -> Bool {
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
        guard let fmt = best else { return false }
        do {
            try device.lockForConfiguration()
            // Order matters inside the lock too: assigning `activeFormat` resets the
            // frame-duration limits to the new format's defaults, so the fps lock has
            // to follow it.
            device.activeFormat = fmt
            let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
            let applied = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            debugPrint("[Capture] activeFormat \(applied.width)x\(applied.height) @\(frameRate.rawValue)fps")
            return applied.width == targetW && applied.height == targetH
        } catch {
            debugPrint("[Capture] format lock failed: \(error)")
            return false
        }
    }

    // MARK: - Session control

    func startSession() {
        sessionQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func setMirroring(enabled: Bool) {
        if let conn = movieOutput.connection(with: .video), conn.isVideoMirroringSupported {
            conn.isVideoMirrored = enabled
        }
    }

    // MARK: - Recording

    func startRecording(to url: URL, lockExposure: Bool) {
        if movieOutput.isRecording {
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        currentOutputURL = url
        segmentURLs = [url]
        baseRecordingID = UUID()
        isPausedFlag = false
        // Lock exposure synchronously on the caller's actor, before dispatching.
        // `MainActor.assumeIsolated` used to wrap this inside `sessionQueue.async`,
        // but that call is a *precondition* that the current executor is already
        // the main actor — it never hops. On `com.onetake.session` it tripped
        // `_dispatch_assert_queue_fail` and crashed every recording start.
        // Doing the lock here keeps the original ordering (exposure settles
        // before the file opens) with no isolation claim at all.
        if lockExposure {
            lockDeviceExposure()
        }
        let delegate: AVCaptureFileOutputRecordingDelegate = self
        sessionQueue.async { [movieOutput, delegate] in
            movieOutput.startRecording(to: url, recordingDelegate: delegate)
        }
    }

    /// Called from the caller's actor before recording starts. `videoDevice` is
    /// written once during `configure`, which every caller awaits first, so the
    /// read here cannot race that write.
    private func lockDeviceExposure() {
        guard let device = videoDevice else { return }
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

    func stopRecording() {
        isPausedFlag = false
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            sessionQueue.async { [weak self] in self?.restoreLocks() }
        }
    }

    func pauseRecording() {
        isPausedFlag = true
        // iOS 18.6 — public API (AVCaptureFileOutput.pauseRecording)
        if #available(iOS 18.0, *) {
            movieOutput.pauseRecording()
            debugPrint("[Capture] native pause")
            return
        }
        // Fallback: stop current segment and prepare for new segment on resume
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            debugPrint("[Capture] fallback pause — stopped segment")
        }
    }

    func resumeRecording() {
        isPausedFlag = false
        if #available(iOS 18.0, *) {
            movieOutput.resumeRecording()
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
        let delegate: AVCaptureFileOutputRecordingDelegate = self
        sessionQueue.async { [movieOutput, delegate] in
            movieOutput.startRecording(to: segURL, recordingDelegate: delegate)
        }
        debugPrint("[Capture] fallback resume — new segment \(segURL.lastPathComponent)")
    }

    func isPaused() -> Bool {
        isPausedFlag
    }

    /// If segments were used (fallback), merge them into originalURL's directory and return merged file. Otherwise return nil (caller
    /// should use original file).
    func finalizeSegmentsIfNeeded(originalURL: URL) async -> URL? {
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
        session.shouldOptimizeForNetworkUse = false
        do {
            try await session.export(to: mergedURL, as: .mp4)
        } catch {
            debugPrint("[Capture] merge failed: \(error.localizedDescription)")
            return nil
        }
        // New API throws on failure, so reaching here means completed — cleanup
        for url in existing {
            try? FileManager.default.removeItem(at: url)
        }
        if let dir = existing.first?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
        // Also remove original first segment if different from merged
        try? FileManager.default.removeItem(at: originalURL)
        return mergedURL
    }

    private func restoreLocks() {
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
    }

    // MARK: - Supported combos helper

    func supportedCombinations() -> [(resolution: Resolution, frameRate: FrameRate, hdr: Bool)] {
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
    }
}
