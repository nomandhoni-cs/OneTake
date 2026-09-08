//
//  ReactionCaptureService.swift
//  OneTake
//
//  Owns: Reaction capture orchestration — movie-file camera recording plus
//  post-capture export lifecycle (progress, retry, temp files, BG task).
//  Why: Capture-first architecture — recording composes the proven
//  `CaptureService` movie path (teleprompter-grade reliability) while heavy
//  segmentation/encoding lives in `ReactionExportJob`, where failure costs a
//  retry instead of a ruined take.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/capture-first-reaction-pipeline/specs/reaction-post-processing/spec.md
//
import AVFoundation
import Foundation
import Observation
import UIKit

/// Frozen inputs for an export attempt — kept so failure can retry identically.
struct PendingExport {
    var rawURL: URL
    var style: ReactionStyle
    var bgVideoURL: URL?
    var bgPhotoURL: URL?
    var bgVolume: Float
    var duckEnabled: Bool
    var micMuted: Bool
}

@Observable
@MainActor
final class ReactionCaptureService: NSObject {
    // MARK: - Capture state

    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var permissionDenied = false
    private(set) var errorMessage: String?

    // MARK: - Export state

    /// 0...1 while processing; nil when idle.
    private(set) var exportProgress: Double?
    private(set) var exportError: String?
    private(set) var pendingExport: PendingExport?

    /// Proven movie-file camera path (1080p30 SDR for reactions).
    let camera = CaptureService()
    let background = BackgroundSource()
    /// Export settings (volume slider, duck toggle, mic mute) + meters legacy.
    let mixer = ReactionAudioMixer()
    let audioMeter = AudioSessionService()
    /// Live framing knobs; snapshotted when export starts.
    var style = ReactionStyle()

    /// Photo BG file for export (video BGs resolve via `audioSourceURL`).
    private var bgPhotoURL: URL?
    private var recordingURL: URL?
    private var exportJob: ReactionExportJob?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Permission

    func checkPermission() -> CapturePermission {
        camera.checkPermission()
    }

    func requestPermission() async -> Bool {
        await camera.requestPermission()
    }

    // MARK: - Session

    func configure() async {
        switch checkPermission() {
        case .notDetermined:
            guard await requestPermission() else {
                permissionDenied = true
                return
            }
        case .denied:
            permissionDenied = true
            return
        case .authorized:
            break
        }
        await camera.configure(resolution: .hd1080p, frameRate: .standard, enableHDR: false)
        camera.startSession()
    }

    func startSession() {
        camera.startSession()
    }

    func stopSession() {
        camera.stopSession()
        audioMeter.stopMetering()
    }

    /// Live mirror toggle for the front camera (preview + raw file).
    func setMirroring(enabled: Bool) {
        camera.setMirroring(enabled: enabled)
    }

    // MARK: - Background picks

    /// Applies a Photos pick; keeps the previous BG on DRM/unreadable errors.
    func applyPickedBackground(_ picked: PickedBackground) {
        Task { @MainActor in
            do {
                if picked.isVideo {
                    try await background.setVideo(url: picked.fileURL, localID: picked.localID)
                    bgPhotoURL = nil
                } else if let data = try? Data(contentsOf: picked.fileURL), let image = UIImage(data: data) {
                    background.setImage(image, localID: picked.localID)
                    bgPhotoURL = picked.fileURL
                } else {
                    throw BackgroundSourceError.unreadable
                }
                if !isRecording {
                    background.play()
                }
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    // MARK: - Recording (movie file)

    /// Starts a reaction recording. Returns `false` when preconditions fail
    /// (no background selected) with `errorMessage` set.
    func startRecording(to url: URL) -> Bool {
        guard background.media != nil else {
            errorMessage = "Pick a background first — tap BG Media."
            return false
        }
        recordingURL = url
        mixer.reset()
        // Linear BG timeline during recording: hold the last frame at the end
        // instead of looping, so export maps camera→BG time 1:1.
        background.loopEnabled = false
        background.play()
        background.liveVolume = mixer.bgVolume
        audioMeter.startMetering()
        camera.startRecording(to: url, lockExposure: true)
        isRecording = true
        isPaused = false
        return true
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        camera.pauseRecording()
        background.pause()
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        camera.resumeRecording()
        background.play()
    }

    /// Stops the movie file (merging pause segments) and returns the raw URL.
    func stopCapture() async -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        isPaused = false
        background.pause()
        background.loopEnabled = true
        audioMeter.stopMetering()
        camera.stopRecording()
        guard let url = recordingURL else { return nil }
        recordingURL = nil
        if let merged = await camera.finalizeSegmentsIfNeeded(originalURL: url) {
            return merged
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Cancels the take and deletes the partial raw file.
    func discardRecording() {
        isRecording = false
        isPaused = false
        background.pause()
        background.loopEnabled = true
        audioMeter.stopMetering()
        camera.stopRecording()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    func clearError() {
        errorMessage = nil
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    // MARK: - Export

    /// Runs the post-capture job: temp file → atomic move into `Takes/` +
    /// raw cleanup on success; raw kept + `exportError`/`pendingExport` set on
    /// failure. Returns the final take URL or `nil`.
    func startExport(rawURL: URL) async -> URL? {
        exportError = nil
        let pending = PendingExport(
            rawURL: rawURL,
            style: style,
            bgVideoURL: background.audioSourceURL,
            bgPhotoURL: bgPhotoURL,
            bgVolume: mixer.bgVolume,
            duckEnabled: mixer.duckEnabled,
            micMuted: mixer.micMuted
        )
        guard hasRoomForExport(of: rawURL) else {
            pendingExport = pending
            exportError = "Not enough free space — export needs about twice the recording size. Free some space and retry."
            return nil
        }
        return await runPending(pending)
    }

    /// Re-runs the last failed/cancelled export with identical inputs.
    func retryExport() async -> URL? {
        guard let pending = pendingExport else { return nil }
        exportError = nil
        guard FileManager.default.fileExists(atPath: pending.rawURL.path) else {
            exportError = "The raw recording is gone — it may have been deleted."
            pendingExport = nil
            return nil
        }
        return await runPending(pending)
    }

    func cancelExport() {
        exportJob?.cancel()
    }

    /// Parks a raw file for later processing (e.g., after a backgrounded
    /// stop) without starting export — the UI offers Process/Discard.
    func parkRaw(_ rawURL: URL) {
        pendingExport = PendingExport(
            rawURL: rawURL,
            style: style,
            bgVideoURL: background.audioSourceURL,
            bgPhotoURL: bgPhotoURL,
            bgVolume: mixer.bgVolume,
            duckEnabled: mixer.duckEnabled,
            micMuted: mixer.micMuted
        )
    }

    /// Deletes the kept raw file and clears the pending export.
    func discardRaw() {
        if let pending = pendingExport {
            try? FileManager.default.removeItem(at: pending.rawURL)
        }
        pendingExport = nil
        exportError = nil
        exportProgress = nil
    }

    func clearExportError() {
        exportError = nil
    }

    private func runPending(_ pending: PendingExport) async -> URL? {
        pendingExport = pending
        exportProgress = 0
        beginBGTask()
        defer { endBGTask() }
        let job = ReactionExportJob()
        exportJob = job
        job.onProgress = { [weak self] progress in
            Task { @MainActor [weak self] in self?.exportProgress = progress }
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reaction-\(UUID().uuidString).mp4")
        let input = ReactionExportInput(
            rawURL: pending.rawURL,
            bgVideoURL: pending.bgVideoURL,
            bgPhotoURL: pending.bgPhotoURL,
            style: pending.style,
            bgVolume: pending.bgVolume,
            duckEnabled: pending.duckEnabled,
            micMuted: pending.micMuted,
            tempURL: tempURL
        )
        do {
            let result = try await job.run(input)
            if let note = result.note {
                debugPrint("[ReactionExport] \(note)")
            }
            let finalURL = ExportService.takesDirectory().appendingPathComponent("\(UUID().uuidString).mp4")
            try FileManager.default.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: result.outputURL, to: finalURL)
            try? FileManager.default.removeItem(at: pending.rawURL)
            exportProgress = nil
            pendingExport = nil
            exportJob = nil
            return finalURL
        } catch is CancellationError {
            exportProgress = nil
            exportJob = nil
            return nil
        } catch {
            exportProgress = nil
            exportJob = nil
            exportError = error.localizedDescription
            return nil
        }
    }

    private func hasRoomForExport(of rawURL: URL) -> Bool {
        let values = try? rawURL.resourceValues(forKeys: [.fileSizeKey])
        let rawBytes = Int64(values?.fileSize ?? 50_000_000)
        let need = rawBytes * 2 + 50_000_000
        let free = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()))?[.systemFreeSize] as? Int64 ?? 0
        return free > need
    }

    private func beginBGTask() {
        endBGTask()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "reaction-export") { [weak self] in
            Task { @MainActor [weak self] in self?.cancelExport() }
        }
    }

    private func endBGTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}
