//
//  ExportService.swift
//  OneTake
//

//  See: docs/ARCHITECTURE.md §5 + openspec/specs/trim-color-export/spec.md
import AVFoundation
import CoreImage
import Metal
import Photos
import UIKit

enum ExportError: LocalizedError {
    case invalidTimeRange
    case sessionCreationFailed
    case exportFailed(String)
    case noSource

    var errorDescription: String? {
        switch self {
        case .invalidTimeRange: "Invalid trim range."
        case .sessionCreationFailed: "Could not create export session."
        case let .exportFailed(s): "Export failed: \(s)"
        case .noSource: "Source video not found."
        }
    }
}

final class ExportService {
    static let shared = ExportService()

    /// Singleton CIContext reused per design (Metal-backed)
    private lazy var ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    // MARK: - Trim-only passthrough (sub-second)

    func exportPassthrough(
        sourceURL: URL,
        timeRange: CMTimeRange,
        outputURL: URL
    ) async throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { throw ExportError.noSource }
        guard timeRange.duration.seconds >= 1 else { throw ExportError.invalidTimeRange }

        // Clean existing output
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ExportError.sessionCreationFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = timeRange
        session.shouldOptimizeForNetworkUse = false

        await session.export()

        if let error = session.error {
            throw ExportError.exportFailed(error.localizedDescription)
        }
        guard session.status == .completed else {
            throw ExportError.exportFailed("status \(session.status.rawValue)")
        }
        return outputURL
    }

    // MARK: - Trim + LUT (re-encode via AVVideoComposition + CIFilter)

    func exportWithLUT(
        sourceURL: URL,
        timeRange: CMTimeRange,
        lutPreset: LUTPreset,
        outputURL: URL
    ) async throws -> URL {
        if lutPreset == .natural {
            return try await exportPassthrough(sourceURL: sourceURL, timeRange: timeRange, outputURL: outputURL)
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else { throw ExportError.noSource }
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        else {
            throw ExportError.exportFailed("Missing tracks")
        }

        let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        try compVideo?.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        // Audio may be shorter; use intersection
        let audioRange = try await CMTimeRange(
            start: timeRange.start,
            duration: min(timeRange.duration, audioTrack.load(.timeRange).duration)
        )
        try? compAudio?.insertTimeRange(audioRange, of: audioTrack, at: .zero)

        compVideo?.preferredTransform = try await videoTrack.load(.preferredTransform)

        // Video composition with CIFilter
        let videoComposition = AVMutableVideoComposition(asset: composition) { request in
            var image = request.sourceImage.clampedToExtent()
            if let filtered = LUTCubeLoader.filter(for: lutPreset, inputImage: image) {
                image = filtered.cropped(to: request.sourceImage.extent)
            }
            request.finish(with: image, context: nil)
        }

        // Render size from natural size
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let size = naturalSize.applying(transform)
        videoComposition.renderSize = CGSize(width: abs(size.width), height: abs(size.height))
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.sessionCreationFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = false

        await session.export()

        if let error = session.error {
            throw ExportError.exportFailed(error.localizedDescription)
        }
        guard session.status == .completed else {
            throw ExportError.exportFailed("status \(session.status.rawValue)")
        }
        return outputURL
    }

    // MARK: - Blade-aware export (trim + split + LUT in one composition)

    /// Exports `take` honoring `trimRange` and `bladeCuts`. Falls back to the
    /// existing passthrough / single-filter path when `bladeSegments` is a single
    /// range. Used by Review when blade editing is active.
    func exportTake(_ take: Take, outputURL: URL) async throws -> URL {
        let segments = take.bladeSegments()
        let lut = LUTPreset(rawValue: take.lutPreset) ?? .natural
        let sourceURL = take.fileURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { throw ExportError.noSource }
        try? FileManager.default.removeItem(at: outputURL)

        // Single-segment fast path: reuse existing single-range exports
        if segments.count == 1, let sole = segments.first {
            if lut == .natural {
                return try await exportPassthrough(sourceURL: sourceURL, timeRange: sole, outputURL: outputURL)
            } else {
                return try await exportWithLUT(sourceURL: sourceURL, timeRange: sole, lutPreset: lut, outputURL: outputURL)
            }
        }

        // Multi-segment composition
        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.exportFailed("Missing video track")
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ExportError.sessionCreationFailed }
        let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var cursor = CMTime.zero
        for segment in segments {
            try compVideo.insertTimeRange(segment, of: videoTrack, at: cursor)
            if let audioTrack, let compAudio {
                // Clamp audio range to its duration
                let audioDuration = try await audioTrack.load(.timeRange).duration
                // Only insert if segment overlaps audio
                if segment.start < audioDuration {
                    let audioSlice = CMTimeRange(
                        start: segment.start,
                        duration: min(segment.duration, audioDuration - segment.start)
                    )
                    if audioSlice.duration.seconds > 0 {
                        try? compAudio.insertTimeRange(audioSlice, of: audioTrack, at: cursor)
                    }
                }
            }
            cursor = CMTimeAdd(cursor, segment.duration)
        }
        compVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let size = naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(size.width), height: abs(size.height))

        let useLUT = lut != .natural
        var videoComposition: AVMutableVideoComposition?
        if useLUT {
            videoComposition = AVMutableVideoComposition(asset: composition) { request in
                var image = request.sourceImage.clampedToExtent()
                if let filtered = LUTCubeLoader.filter(for: lut, inputImage: image) {
                    image = filtered.cropped(to: request.sourceImage.extent)
                }
                request.finish(with: image, context: nil)
            }
            videoComposition?.renderSize = renderSize
            videoComposition?.frameDuration = CMTime(value: 1, timescale: 30)
        }

        let preset = useLUT ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ExportError.sessionCreationFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        if let vc = videoComposition {
            session.videoComposition = vc
        }
        session.shouldOptimizeForNetworkUse = false
        await session.export()
        if let error = session.error {
            throw ExportError.exportFailed(error.localizedDescription)
        }
        guard session.status == .completed else { throw ExportError.exportFailed("status \(session.status.rawValue)") }
        return outputURL
    }

    // MARK: - Photos save

    func saveToPhotos(fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.exportFailed("Photos permission denied. Enable in Settings → Privacy → Photos.")
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }
        // Cleanup sandbox cache after successful save: remove source file
        // Caller decides whether to delete source vs exported file; we clean the exported temp
        // The design says delete sandbox source on success — caller should handle that
    }

    // MARK: - Helpers

    static func tempOutputURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("onetake-\(UUID().uuidString).mp4")
    }

    static func takesDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cleanupTempFiles(olderThan days: Int = 7) {
        let tmp = FileManager.default.temporaryDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(Double(-days * 86400))
        for url in files where url.lastPathComponent.hasPrefix("onetake-") {
            if let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate, date < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}
