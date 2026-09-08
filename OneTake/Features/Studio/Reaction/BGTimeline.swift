//
//  BGTimeline.swift
//  OneTake
//
//  Owns: Deterministic background-video frame lookup for export — pulls
//  frames by camera timestamp, looping short assets, trimming long ones.
//  Why: Split from `ReactionExportJob` to keep both files under the
//  `file_length` lint budget; pure mapping plus confined reader state.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/capture-first-reaction-pipeline/specs/reaction-post-processing/spec.md
//
import AVFoundation
import CoreImage
import Foundation

/// Deterministic BG video timeline for export — pulls frames by camera
/// timestamp, looping the asset when shorter, stopping at camera end.
///
/// All reader state is confined to the caller's (worker) queue.
final class BGTimeline {
    /// Pure loop mapping, unit-tested: folds camera time into one BG pass.
    static func loopedTime(cameraTime: CMTime, bgDuration: CMTime) -> CMTime {
        guard bgDuration.seconds > 0, cameraTime.seconds >= 0 else { return .zero }
        let folded = cameraTime.seconds.truncatingRemainder(dividingBy: bgDuration.seconds)
        return CMTime(seconds: folded, preferredTimescale: cameraTime.timescale)
    }

    private let url: URL
    private let duration: CMTime
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var stashed: (time: CMTime, image: CIImage)?

    init(url: URL?) {
        // Photo BG is composited by the caller as a static image — a nil URL
        // here simply resolves every frame to nil.
        guard let url else {
            self.url = URL(fileURLWithPath: "/dev/null")
            duration = .zero
            return
        }
        self.url = url
        let asset = AVURLAsset(url: url)
        duration = asset.legacyTracks(withMediaType: .video).first?.legacyTimeRange.duration ?? .zero
        startReader()
    }

    /// BG frame for a camera timestamp. Camera time folds into one BG pass
    /// (`loopedTime`); when the reader drains it restarts from zero, so short
    /// BGs loop seamlessly. Returns `nil` only when no BG video exists.
    func frame(at cameraTime: CMTime) -> CIImage? {
        guard duration.seconds > 0 else { return nil }
        let target = Self.loopedTime(cameraTime: cameraTime, bgDuration: duration)
        if let hit = advance(to: target) {
            return hit
        }
        // Reader drained mid-take → restart the loop and continue past the seam.
        stashed = nil
        startReader()
        return advance(to: target)
    }

    /// Advances the reader until the buffered frame reaches `target`.
    private func advance(to target: CMTime) -> CIImage? {
        while true {
            if let hit = stashed, hit.time >= target {
                return hit.image
            }
            guard let next = readNext() else {
                return stashed?.image
            }
            stashed = next
        }
    }

    func close() {
        reader?.cancelReading()
        reader = nil
        output = nil
        stashed = nil
    }

    private func startReader() {
        let asset = AVURLAsset(url: url)
        guard let track = asset.legacyTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset)
        else {
            self.reader = nil
            output = nil
            return
        }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        guard reader.canAdd(out), reader.startReading() else {
            self.reader = nil
            output = nil
            return
        }
        reader.add(out)
        self.reader = reader
        output = out
    }

    /// Reads one fresh buffer (stash is managed by `advance`, not here).
    private func readNext() -> (time: CMTime, image: CIImage)? {
        guard let output, let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample)
        else { return nil }
        return (CMSampleBufferGetPresentationTimeStamp(sample), CIImage(cvPixelBuffer: buffer))
    }
}

extension AVAssetReader {
    /// Next track sample, or `nil` when drained/failed.
    func output() -> CMSampleBuffer? {
        outputs.compactMap { $0 as? AVAssetReaderTrackOutput }.first?.copyNextSampleBuffer()
    }
}
