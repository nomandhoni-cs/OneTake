//
//  BGTimelineReaderTests.swift
//  OneTakeTests
//
//  Owns: Cover for `BGTimeline`'s reader path — the half that actually pulls
//  background frames off disk.
//  Why: `BGTimeline.loopedTime` was unit-tested, but the surrounding
//  `AVAssetReader` plumbing never was, so a background video that silently
//  produced no frames would ship green. These drive a real asset end to end.
//  See: docs/ARCHITECTURE.md §6
//
import AVFoundation
import CoreImage
import CoreMedia
import Foundation
@testable import OneTake
import Testing

@Suite(.serialized)
struct BGTimelineReaderTests {
    private enum FixtureError: Error {
        case writerStalled
    }

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bg-\(UUID().uuidString)-\(name)")
    }

    private func solidPixelBuffer(width: Int, height: Int, red: UInt8) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            == kCVReturnSuccess, let buffer
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = y * bytesPerRow + x * 4
                ptr[offset] = 20
                ptr[offset + 1] = 60
                ptr[offset + 2] = red
                ptr[offset + 3] = 255
            }
        }
        return buffer
    }

    /// Plain video-only background clip, `frames` long at `fps`.
    private func makeBackgroundClip(frames: Int = 20, fps: Int32 = 10) throws -> URL {
        let url = tempURL("bg.mp4")
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 128,
            AVVideoHeightKey: 96,
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 128,
            kCVPixelBufferHeightKey as String: 96,
        ])
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for index in 0 ..< frames {
            guard let pb = solidPixelBuffer(width: 128, height: 96, red: UInt8((30 + index * 9) % 256)) else { continue }
            var spins = 0
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
                spins += 1
                if spins > 500 {
                    throw FixtureError.writerStalled
                }
            }
            adaptor.append(pb, withPresentationTime: CMTime(value: Int64(index), timescale: fps))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        _ = done.wait(timeout: .now() + 30)
        return url
    }

    // MARK: - Tests

    /// The core contract: a real background video must yield a frame. If the
    /// reader is misconfigured this returns nil and every reaction export
    /// composites over an empty background.
    @Test func backgroundVideoYieldsFrames() throws {
        let url = try makeBackgroundClip()
        defer { try? FileManager.default.removeItem(at: url) }

        let timeline = BGTimeline(url: url)
        defer { timeline.close() }

        let frame = timeline.frame(at: CMTime(value: 0, timescale: 10))
        #expect(frame != nil, "BGTimeline returned no frame for a valid background video")
    }

    /// Frames must keep coming as the camera clock advances, not just at t=0.
    @Test func backgroundVideoYieldsFramesAcrossTheTake() throws {
        let url = try makeBackgroundClip()
        defer { try? FileManager.default.removeItem(at: url) }

        let timeline = BGTimeline(url: url)
        defer { timeline.close() }

        var hits = 0
        for tick in 0 ..< 10 {
            if timeline.frame(at: CMTime(value: Int64(tick), timescale: 10)) != nil {
                hits += 1
            }
        }
        #expect(hits == 10, "expected a frame at every camera tick, got \(hits)/10")
    }

    /// A camera longer than the background must loop rather than go blank.
    @Test func shortBackgroundLoopsPastItsEnd() throws {
        let url = try makeBackgroundClip(frames: 10, fps: 10) // 1s of background
        defer { try? FileManager.default.removeItem(at: url) }

        let timeline = BGTimeline(url: url)
        defer { timeline.close() }

        _ = timeline.frame(at: CMTime(value: 0, timescale: 10))
        // 2.5s in — well past the 1s background, so this exercises the loop seam.
        let looped = timeline.frame(at: CMTime(value: 25, timescale: 10))
        #expect(looped != nil, "background did not loop past its own duration")
    }

    /// A nil URL (photo background) resolves to nil frames without crashing —
    /// the caller composites the still image itself.
    @Test func nilURLResolvesToNilFrames() {
        let timeline = BGTimeline(url: nil)
        defer { timeline.close() }
        #expect(timeline.frame(at: .zero) == nil)
    }
}
