//
//  ExportFrameRateTests.swift
//  OneTakeTests
//
//  Owns: Characterization cover for the graded-export frame rate.
//  Why: 4K60 is a paid Pro claim, so the LUT path must never quietly resample.
//  These lock the observed contract — source rate in, same rate out — so any
//  future change to the composition or export preset that starts resampling
//  shows up here rather than in a customer's 60 fps footage.
//  See: docs/ARCHITECTURE.md §6 (Export)
//
import AVFoundation
import CoreMedia
import Foundation
@testable import OneTake
import Testing

/// Serialized: each case drives the simulator's software H.264 encoder, which
/// stalls when several exports run at once (same rationale as the Reaction suite).
@Suite(.serialized)
struct ExportFrameRateTests {
    private enum FixtureError: Error {
        case writerStalled
    }

    // MARK: - Fixtures

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fps-\(UUID().uuidString)-\(name)")
    }

    private func waitReady(_ input: AVAssetWriterInput) throws {
        var spins = 0
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.01)
            spins += 1
            if spins > 500 {
                throw FixtureError.writerStalled
            }
        }
    }

    private func solidPixelBuffer(width: Int, height: Int, red: UInt8) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
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
                ptr[offset] = 40 // B
                ptr[offset + 1] = 90 // G
                ptr[offset + 2] = red // R
                ptr[offset + 3] = 255
            }
        }
        return buffer
    }

    /// Writes a clip of `frames` at exactly `fps`, with an AAC track because
    /// `exportWithLUT` requires both a video and an audio track.
    private func makeClip(url: URL, frames: Int, fps: Int32) throws -> URL {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 128,
            AVVideoHeightKey: 96,
        ])
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 128,
            kCVPixelBufferHeightKey as String: 96,
        ])
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ])
        audioInput.expectsMediaDataInRealTime = false
        writer.add(audioInput)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for index in 0 ..< frames {
            guard let pb = solidPixelBuffer(width: 128, height: 96, red: UInt8((40 + index * 3) % 256)) else { continue }
            try waitReady(videoInput)
            adaptor.append(pb, withPresentationTime: CMTime(value: Int64(index), timescale: fps))
        }
        videoInput.markAsFinished()

        if let pcmFormat = ReactionExportJob.pcmFormat() {
            let total = Int(44100.0 * Double(frames) / Double(fps))
            var offset = 0
            while offset < total {
                let count = min(1024, total - offset)
                let samples = [Float](repeating: 0, count: count)
                if let sb = PCMSampleBufferFactory.makeBuffer(
                    samples: samples,
                    presentationTime: CMTime(value: Int64(offset), timescale: 44100),
                    format: pcmFormat
                ) {
                    try waitReady(audioInput)
                    audioInput.append(sb)
                }
                offset += count
            }
        }
        audioInput.markAsFinished()

        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        _ = done.wait(timeout: .now() + 30)
        return url
    }

    private func nominalFrameRate(of url: URL) async throws -> Float {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return 0 }
        return try await track.load(.nominalFrameRate)
    }

    // MARK: - Tests

    /// A 60 fps source graded with a LUT must come out at 60 fps.
    @Test func gradedExportPreservesSixtyFPS() async throws {
        let source = try makeClip(url: tempURL("src60.mp4"), frames: 60, fps: 60)
        let output = tempURL("out60.mp4")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        _ = try await ExportService().exportWithLUT(
            sourceURL: source,
            timeRange: CMTimeRange(start: .zero, duration: duration),
            lutPreset: .cinematicContrast,
            outputURL: output
        )

        let fps = try await nominalFrameRate(of: output)
        #expect(fps > 45, "expected ~60 fps, got \(fps)")
    }

    /// A 30 fps source must stay 30 — the pipeline preserves, never normalizes.
    @Test func gradedExportPreservesThirtyFPS() async throws {
        let source = try makeClip(url: tempURL("src30.mp4"), frames: 30, fps: 30)
        let output = tempURL("out30.mp4")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        _ = try await ExportService().exportWithLUT(
            sourceURL: source,
            timeRange: CMTimeRange(start: .zero, duration: duration),
            lutPreset: .cinematicContrast,
            outputURL: output
        )

        let fps = try await nominalFrameRate(of: output)
        #expect(fps > 20 && fps < 45, "expected ~30 fps, got \(fps)")
    }

    /// 4K is a Pro selling point, so the capture settings that feed it must
    /// keep reporting true UHD dimensions.
    @Test func fourKResolutionIsTrueUHD() {
        #expect(Resolution.uhd4K.pixelSize.width == 3840)
        #expect(Resolution.uhd4K.pixelSize.height == 2160)
        #expect(Resolution.hd1080p.pixelSize.width == 1920)
        #expect(Resolution.hd1080p.pixelSize.height == 1080)
    }
}
