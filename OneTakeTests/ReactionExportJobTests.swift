import AVFoundation
import CoreImage
import CoreMedia
import Foundation
@testable import OneTake
import Testing
import Vision

/// Fake segmentation: deterministic full-white matte (fast, no ANE).
final class FakeMask: MaskProviding { var delay: TimeInterval = 0

    func mask(from pixelBuffer: CVPixelBuffer, using handler: VNSequenceRequestHandler) throws -> CIImage? {
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        return CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
    }
}

/// Export tests run serialized: each spins up H.264 + ANE/CPU segmentation,
/// and parallel execution stalls the simulator software encoder.
@Suite(.serialized)
struct ReactionExportJobTests {
    private enum FixtureError: Error {
        case writerStalled
    }

    // MARK: - Fixtures

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("export-test-\(UUID().uuidString)-\(name)")
    }

    private func solidPixelBuffer(width: Int, height: Int, red: UInt8) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
              let pb = buffer
        else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        for row in 0 ..< height {
            let ptr = base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt8.self)
            for col in 0 ..< width {
                ptr[col * 4] = 30
                ptr[col * 4 + 1] = 30
                ptr[col * 4 + 2] = red
                ptr[col * 4 + 3] = 255
            }
        }
        return pb
    }

    private func finish(writer: AVAssetWriter) {
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
    }

    /// Bounded writer-ready wait — a stalled writer fails fast, never hangs.
    /// Generous deadline: the simulator software encoder stalls under load.
    private func waitReady(_ input: AVAssetWriterInput) throws {
        let deadline = Date().addingTimeInterval(30)
        while !input.isReadyForMoreMediaData {
            guard Date() < deadline else { throw FixtureError.writerStalled }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    /// Tiny camera clip: solid frames + optional 440 Hz tone, `frames` at `fps`.
    @discardableResult
    private func makeCameraClip(url: URL, frames: Int = 10, fps: Int32 = 10, withAudio: Bool = true) throws -> URL {
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
        var audioInput: AVAssetWriterInput?
        var pcmFormat: CMFormatDescription?
        if withAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
            pcmFormat = ReactionExportJob.pcmFormat()
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for index in 0 ..< frames {
            guard let pb = solidPixelBuffer(width: 128, height: 96, red: UInt8((50 + index * 10) % 256)) else { continue }
            try waitReady(videoInput)
            adaptor.append(pb, withPresentationTime: CMTime(value: Int64(index), timescale: fps))
        }
        videoInput.markAsFinished()
        if let audioInput, let pcmFormat {
            let total = Int(44100.0 * Double(frames) / Double(fps))
            var offset = 0
            while offset < total {
                let count = min(1024, total - offset)
                var samples = [Float](repeating: 0, count: count)
                for i in 0 ..< count {
                    samples[i] = sin(2 * Float.pi * 440 * Float(offset + i) / 44100) * 0.5
                }
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
            audioInput.markAsFinished()
        }
        finish(writer: writer)
        return url
    }

    private func makeInput(
        rawURL: URL,
        bgVideoURL: URL? = nil,
        bgPhotoURL: URL? = nil,
        mask: FakeMask = FakeMask()
    ) -> (ReactionExportJob, ReactionExportInput) {
        let job = ReactionExportJob(maskProvider: mask)
        let input = ReactionExportInput(
            rawURL: rawURL,
            bgVideoURL: bgVideoURL,
            bgPhotoURL: bgPhotoURL,
            style: ReactionStyle(),
            bgVolume: 0.4,
            duckEnabled: true,
            micMuted: false,
            tempURL: tempURL("out.mp4")
        )
        return (job, input)
    }

    private func trackDuration(_ url: URL, mediaType: AVMediaType) -> CMTime {
        let asset = AVURLAsset(url: url)
        return asset.tracks(withMediaType: mediaType).first?.timeRange.duration ?? .invalid
    }

    // MARK: - Job behavior

    @Test func exportCompletesWithMonotonicProgress() async throws {
        let raw = try makeCameraClip(url: tempURL("raw.mp4"))
        let (job, input) = makeInput(rawURL: raw)
        let lock = NSLock()
        var points: [Double] = []
        job.onProgress = { progress in
            lock.lock()
            points.append(progress)
            lock.unlock()
        }
        let result = try await job.run(input)
        #expect(FileManager.default.fileExists(atPath: result.outputURL.path))
        #expect(result.downgradedQuality == false)
        let videoDur = trackDuration(result.outputURL, mediaType: .video)
        #expect(abs(videoDur.seconds - 1.0) < 0.4)
        lock.lock()
        let seen = points
        lock.unlock()
        #expect(seen.count >= 2)
        #expect(seen.last == 1.0)
        for (prev, next) in zip(seen, seen.dropFirst()) {
            #expect(next >= prev)
        }
        try? FileManager.default.removeItem(at: raw)
        try? FileManager.default.removeItem(at: result.outputURL)
    }

    @Test func cancelDeletesTemp() async throws {
        let raw = try makeCameraClip(url: tempURL("raw.mp4"), frames: 12)
        let mask = FakeMask()
        mask.delay = 0.05
        let (job, input) = makeInput(rawURL: raw, mask: mask)
        let task = Task { try await job.run(input) }
        try await Task.sleep(nanoseconds: 300_000_000)
        job.cancel()
        do {
            _ = try await task.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
        #expect(FileManager.default.fileExists(atPath: input.tempURL.path) == false)
        try? FileManager.default.removeItem(at: raw)
    }

    @Test func unreadableRawThrowsAndCleansTemp() async throws {
        let (job, input) = makeInput(rawURL: URL(fileURLWithPath: "/dev/null/missing.mp4"))
        do {
            _ = try await job.run(input)
            Issue.record("expected throw")
        } catch is CancellationError {
            Issue.record("expected export error, not cancellation")
        } catch {
            // Expected: unreadable raw.
        }
        #expect(FileManager.default.fileExists(atPath: input.tempURL.path) == false)
    }

    @Test func audioVideoStayAligned() async throws {
        let raw = try makeCameraClip(url: tempURL("raw.mp4"), frames: 20)
        let (job, input) = makeInput(rawURL: raw)
        let result = try await job.run(input)
        let asset = AVURLAsset(url: result.outputURL)
        let video = try #require(asset.tracks(withMediaType: .video).first)
        let audio = try #require(asset.tracks(withMediaType: .audio).first)
        // Sample-accurate enough: durations agree and both tracks start together.
        #expect(abs(video.timeRange.duration.seconds - audio.timeRange.duration.seconds) < 0.3)
        #expect(abs(video.timeRange.start.seconds - audio.timeRange.start.seconds) < 0.25)
        try? FileManager.default.removeItem(at: raw)
        try? FileManager.default.removeItem(at: result.outputURL)
    }

    // MARK: - BG timeline mapping

    @Test func bgLoopFoldsCameraTime() {
        #expect(BGTimeline.loopedTime(
            cameraTime: CMTime(seconds: 25, preferredTimescale: 600),
            bgDuration: CMTime(seconds: 10, preferredTimescale: 600)
        ).seconds == 5)
        // Longer BG trims naturally (no fold needed).
        #expect(BGTimeline.loopedTime(
            cameraTime: CMTime(seconds: 5, preferredTimescale: 600),
            bgDuration: CMTime(seconds: 30, preferredTimescale: 600)
        ).seconds == 5)
        #expect(BGTimeline.loopedTime(
            cameraTime: CMTime(seconds: 5, preferredTimescale: 600),
            bgDuration: .zero
        ) == .zero)
    }

    // MARK: - Lookahead ducking

    @Test func lookaheadAnticipatesSpeech() {
        let speaking = [Bool](repeating: false, count: 10) + [Bool](repeating: true, count: 10)
        let chunkDuration = 1024.0 / 44100.0
        let gains = LookaheadDucker.gains(
            speaking: speaking,
            ducking: ReactionDucking(),
            lookaheadChunks: 5,
            chunkDuration: chunkDuration
        )
        #expect(gains.count == 20)
        // Chunk 9 is silent but speech starts at 10 within the horizon:
        // the BG is already ducking (causal ducking would still be 1.0).
        #expect(gains[9] < 1.0)
        var causal = ReactionDucking()
        for _ in 0 ..< 10 {
            _ = causal.update(speaking: false, dt: chunkDuration)
        }
        #expect(gains[9] < causal.gain)
        // Deep in the burst the gain bottoms out at the ducked level.
        #expect(abs(gains[19] - 0.3) < 0.01)
    }

    // MARK: - PCM extraction hardening

    @Test func floatSamplesDownmixesStereoWithoutCrashing() {
        // Interleaved stereo L=0.6/R=-0.2 must average to mono ≈ 0.2, never
        // overread the variable-length buffer list (device crash vector).
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr, let format else {
            Issue.record("stereo format setup failed")
            return
        }
        var interleaved = [Float](repeating: 0, count: 2048)
        for index in stride(from: 0, to: interleaved.count, by: 2) {
            interleaved[index] = 0.6
            interleaved[index + 1] = -0.2
        }
        guard let buffer = PCMSampleBufferFactory.makeBuffer(
            samples: interleaved,
            presentationTime: .zero,
            format: format
        ) else {
            Issue.record("stereo buffer setup failed")
            return
        }
        let mono = ReactionExportJob.floatSamples(of: buffer)
        let samples = try? #require(mono)
        #expect(samples?.count == 1024)
        #expect(samples?.allSatisfy { abs($0 - 0.2) < 0.001 } == true)
    }
}
