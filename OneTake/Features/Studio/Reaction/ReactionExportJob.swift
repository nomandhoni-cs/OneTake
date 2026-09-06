//
//  ReactionExportJob.swift
//  OneTake
//
//  Owns: Post-capture reaction export — raw camera file + BG media →
//  composited MP4 with lookahead-ducked audio (reader → segment → composite
//  → writer, fully offline).
//  Why: Capture-first architecture — recording stays on the proven movie-file
//  path while quality (.accurate + sequence handler), retryability, and
//  sample-accurate audio live here, where failure costs a retry, not a take.
//  Runs on a worker queue; progress/cancel cross threads via lock + callback.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/capture-first-reaction-pipeline/specs/reaction-post-processing/spec.md
//
import AVFoundation
import CoreImage
import Foundation
import Vision

/// Inputs frozen at export start (style snapshot, BG references, mix settings).
struct ReactionExportInput: Sendable {
    var rawURL: URL
    var bgVideoURL: URL?
    var bgPhotoURL: URL?
    var style: ReactionStyle
    var bgVolume: Float
    var duckEnabled: Bool
    var micMuted: Bool
    var tempURL: URL
}

/// Export outcome — temp file location plus quality provenance for the UI.
struct ReactionExportResult: Sendable {
    var outputURL: URL
    var downgradedQuality = false
    var note: String?
}

enum ReactionExportError: LocalizedError {
    case unreadableRaw
    case backgroundUnreadable
    case noVideoTrack
    case writerSetup(String)

    var errorDescription: String? {
        switch self {
        case .unreadableRaw:
            "The raw recording couldn't be read. Your original take is kept — try again."
        case .backgroundUnreadable:
            "The background media couldn't be read (it may have been deleted). Pick it again — your recording is kept."
        case .noVideoTrack:
            "The raw recording has no video. Your original take is kept — try again."
        case let .writerSetup(detail):
            "Export couldn't start (\(detail)). Your original take is kept — try again."
        }
    }
}

/// Offline export: segments each camera frame, composites over the BG
/// timeline, and mixes lookahead-ducked audio into one MP4.
///
/// Confinement: all mutable state lives on `workQueue`; `cancel()` is safe
/// from any thread. `maskProvider` defaults to the real Vision path and is
/// injected as a fake in tests for fast deterministic runs.
final class ReactionExportJob: @unchecked Sendable {
    static let canvasSize = CGSize(width: 1080, height: 1920)
    static let sampleRate = 44100.0
    static let chunkFrames = 1024
    /// Downgrade to `.balanced` when `.accurate` is slower than this.
    static let minAcceptableSegmentFPS = 8.0
    static let probeFrames = 30

    /// Progress 0...1, invoked on the worker queue (hop to main as needed).
    var onProgress: ((Double) -> Void)?

    private let maskProvider: any MaskProviding
    private let workQueue = DispatchQueue(label: "com.onetake.reaction-export", qos: .userInitiated)
    private let stateLock = NSLock()
    private var cancelled = false
    private var readerRefs: [AVAssetReader] = []
    private var writerRef: AVAssetWriter?

    init(maskProvider: any MaskProviding = PersonSegmenter()) {
        self.maskProvider = maskProvider
    }

    func run(_ input: ReactionExportInput) async throws -> ReactionExportResult {
        try await withCheckedThrowingContinuation { continuation in
            workQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    try continuation.resume(returning: execute(input))
                } catch {
                    // Cancel/failure must never leave a partial temp file behind.
                    try? FileManager.default.removeItem(at: input.tempURL)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cancel() {
        stateLock.lock()
        cancelled = true
        let readers = readerRefs
        let writer = writerRef
        stateLock.unlock()
        for reader in readers {
            reader.cancelReading()
        }
        writer?.cancelWriting()
    }

    // MARK: - Execute (workQueue)

    private func execute(_ input: ReactionExportInput) throws -> ReactionExportResult {
        try checkCancelled()
        try FileManager.default.createDirectory(at: input.tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: input.tempURL)
        defer {
            stateLock.lock()
            readerRefs.removeAll()
            writerRef = nil
            stateLock.unlock()
        }

        let rawAsset = AVURLAsset(url: input.rawURL)
        guard rawAsset.isReadable else { throw ReactionExportError.unreadableRaw }
        guard let camVideoTrack = rawAsset.tracks(withMediaType: .video).first else {
            throw ReactionExportError.noVideoTrack
        }
        let camAudioTrack = rawAsset.tracks(withMediaType: .audio).first
        let duration = camVideoTrack.timeRange.duration
        let fps = max(camVideoTrack.nominalFrameRate, 1)
        let totalFrames = max(Int((duration.seconds * Double(fps)).rounded()), 1)

        let compositor = ReactionCompositor()
        let bgTimeline = BGTimeline(url: input.bgVideoURL)
        defer { bgTimeline.close() }
        let photoBG: CIImage? = input.bgPhotoURL.flatMap { CIImage(contentsOf: $0) }

        // Camera readers (separate instances so video/audio drain independently).
        let camVideoReader = try makeReader(asset: rawAsset)
        let camVideoOutput = AVAssetReaderTrackOutput(track: camVideoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        guard camVideoReader.canAdd(camVideoOutput) else { throw ReactionExportError.writerSetup("camera video") }
        camVideoReader.add(camVideoOutput)

        // Writer.
        let stack = try makeWriter(tempURL: input.tempURL, hasMic: camAudioTrack != nil)
        let writer = stack.writer
        let videoInput = stack.video
        let adaptor = stack.adaptor
        let audioInput = stack.audio
        let pcmFormat = Self.pcmFormat()
        stateLock.lock()
        writerRef = writer
        stateLock.unlock()

        // Video pass.
        guard camVideoReader.startReading() else { throw ReactionExportError.unreadableRaw }
        register(reader: camVideoReader)
        var videoPass = VideoPass(
            reader: camVideoReader,
            compositor: compositor,
            timeline: bgTimeline,
            photoBG: photoBG,
            handler: VNSequenceRequestHandler(),
            stack: stack,
            totalFrames: totalFrames,
            style: input.style,
            maskProvider: maskProvider,
            onProgress: onProgress,
            checkCancelled: checkCancelled
        )
        try videoPass.run()
        try checkCancelled()
        guard camVideoReader.status == .completed else { throw ReactionExportError.unreadableRaw }

        // Audio pass.
        if camAudioTrack != nil, let audioInput, let pcmFormat {
            try mixAudio(
                rawAsset: rawAsset,
                camAudioTrack: camAudioTrack,
                input: input,
                audioInput: audioInput,
                pcmFormat: pcmFormat
            )
        }

        // Finish.
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        let finishError = finish(writer: writer)
        if let finishError {
            try? FileManager.default.removeItem(at: input.tempURL)
            throw finishError
        }
        onProgress?(1.0)
        var note: String?
        if videoPass.downgraded {
            note = "Used balanced segmentation for speed on this device."
        }
        return ReactionExportResult(outputURL: input.tempURL, downgradedQuality: videoPass.downgraded, note: note)
    }

    /// Assembled writer inputs; kept together so `execute` stays lean.
    private struct WriterStack {
        var writer: AVAssetWriter
        var video: AVAssetWriterInput
        var adaptor: AVAssetWriterInputPixelBufferAdaptor
        var audio: AVAssetWriterInput?
    }

    private func makeWriter(tempURL: URL, hasMic: Bool) throws -> WriterStack {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        } catch {
            throw ReactionExportError.writerSetup(error.localizedDescription)
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(Self.canvasSize.width),
            AVVideoHeightKey: Int(Self.canvasSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw ReactionExportError.writerSetup("video input") }
        writer.add(videoInput)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(Self.canvasSize.width),
            kCVPixelBufferHeightKey as String: Int(Self.canvasSize.height),
        ])
        var audioInput: AVAssetWriterInput?
        if hasMic {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000,
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw ReactionExportError.writerSetup("audio input") }
            writer.add(input)
            audioInput = input
        }
        return WriterStack(writer: writer, video: videoInput, adaptor: adaptor, audio: audioInput)
    }

    // MARK: - Audio (workQueue)

    /// Segmentation fps probe — collects the first frames' inference times
    /// and fires once when `.accurate` is too slow for a sane export pace.
    private struct FPSProbe {
        var samples: [TimeInterval] = []
        private(set) var fired = false

        mutating func add(_ duration: TimeInterval, needed: Int, minFPS: Double) -> Bool {
            guard !fired else { return false }
            samples.append(duration)
            guard samples.count >= needed else { return false }
            fired = true
            let avg = samples.reduce(0, +) / Double(samples.count)
            return avg > 1 / minFPS
        }
    }

    /// One video pass over the camera track. Worker-queue confined.
    private struct VideoPass {
        var reader: AVAssetReader
        var compositor: ReactionCompositor
        var timeline: BGTimeline
        var photoBG: CIImage?
        var handler: VNSequenceRequestHandler
        var stack: WriterStack
        var totalFrames: Int
        var style: ReactionStyle
        var maskProvider: any MaskProviding
        var onProgress: ((Double) -> Void)?
        var checkCancelled: () throws -> Void

        var downgraded = false
        var processed = 0

        mutating func run() throws {
            var sessionStarted = false
            var probe = FPSProbe()
            while let sample = reader.output() {
                try checkCancelled()
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let camPTS = CMSampleBufferGetPresentationTimeStamp(sample)
                let mask = segmentFrame(pixelBuffer, probe: &probe)
                let camera = CIImage(cvPixelBuffer: pixelBuffer)
                let background = photoBG ?? timeline.frame(at: camPTS) ?? ReactionExportJob.solidColor(.black)
                let composite = compositor.composite(
                    camera: camera,
                    mask: style.maskEnabled ? mask : nil,
                    background: background,
                    canvasSize: ReactionExportJob.canvasSize,
                    style: style
                )
                if !sessionStarted {
                    stack.writer.startWriting()
                    stack.writer.startSession(atSourceTime: camPTS)
                    sessionStarted = true
                }
                try append(composite, at: camPTS)
                processed += 1
                onProgress?(min(0.95 * Double(processed) / Double(max(totalFrames, 1)), 0.95))
            }
            guard sessionStarted else { throw ReactionExportError.noVideoTrack }
        }

        /// Segments one frame, downgrading quality once when the probe fires.
        private mutating func segmentFrame(_ pixelBuffer: CVPixelBuffer, probe: inout FPSProbe) -> CIImage? {
            do {
                let start = Date()
                let mask = try maskProvider.mask(from: pixelBuffer, using: handler)
                let slow = probe.add(
                    Date().timeIntervalSince(start),
                    needed: ReactionExportJob.probeFrames,
                    minFPS: ReactionExportJob.minAcceptableSegmentFPS
                )
                if slow {
                    applyDowngrade()
                }
                return mask
            } catch {
                // Single-frame inference failure must not kill the job —
                // composite unmasked for this frame and continue.
                debugPrint("[ExportJob] segmentation failed, continuing unmasked")
                return nil
            }
        }

        private mutating func applyDowngrade() {
            guard let segmenter = maskProvider as? PersonSegmenter else { return }
            segmenter.qualityLevel = .balanced
            downgraded = true
        }

        private func append(_ composite: CIImage, at pts: CMTime) throws {
            // Never skip frames: a dropped frame desyncs A/V and progress.
            // A stalled writer throws (retry path) instead of hanging.
            let deadline = Date().addingTimeInterval(5)
            while !stack.video.isReadyForMoreMediaData {
                try checkCancelled()
                guard Date() < deadline else { throw ReactionExportError.writerSetup("video stalled") }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let pool = stack.adaptor.pixelBufferPool else { return }
            var outBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuffer) == kCVReturnSuccess,
                  let out = outBuffer
            else { return }
            compositor.renderToPixelBuffer(composite, to: out)
            stack.adaptor.append(out, withPresentationTime: pts)
        }
    }

    private func mixAudio(
        rawAsset: AVURLAsset,
        camAudioTrack: AVAssetTrack?,
        input: ReactionExportInput,
        audioInput: AVAssetWriterInput,
        pcmFormat: CMFormatDescription
    ) throws {
        guard let camAudioTrack else { return }
        let mic = try readMonoSamples(asset: rawAsset, track: camAudioTrack, failure: .unreadableRaw)
        guard !mic.samples.isEmpty else { return }

        // A silent BG clip (no audio track) is legitimate → mic-only mix.
        var bgSamples: [Float] = []
        if let bgURL = input.bgVideoURL, let bgTrack = AVURLAsset(url: bgURL).tracks(withMediaType: .audio).first {
            bgSamples = try readMonoSamples(asset: AVURLAsset(url: bgURL), track: bgTrack, failure: .backgroundUnreadable).samples
        }

        // Chunk, lookahead-duck, mix, append.
        let frames = Self.chunkFrames
        let micSamples = mic.samples
        let micStart = mic.start
        let chunkCount = (micSamples.count + frames - 1) / frames
        var speaking: [Bool] = []
        speaking.reserveCapacity(chunkCount)
        for index in 0 ..< chunkCount {
            let slice = micSamples[index * frames ..< min((index + 1) * frames, micSamples.count)]
            let db = ReactionVAD.rmsDB(of: Array(slice))
            speaking.append(!input.micMuted && db > ReactionVAD.speechThresholdDB)
        }
        let chunkDuration = TimeInterval(frames) / Self.sampleRate
        let lookahead = Int((1.0 / chunkDuration).rounded()) // ~1 s horizon
        let gains: [Float] = if input.duckEnabled {
            LookaheadDucker.gains(
                speaking: speaking,
                ducking: ReactionDucking(),
                lookaheadChunks: lookahead,
                chunkDuration: chunkDuration
            )
        } else {
            [Float](repeating: 1.0, count: chunkCount)
        }
        for index in 0 ..< chunkCount {
            try checkCancelled()
            let range = index * frames ..< min((index + 1) * frames, micSamples.count)
            var mixed = [Float](repeating: 0, count: range.count)
            for (offset, mic) in micSamples[range].enumerated() {
                let global = index * frames + offset
                let bg: Float = bgSamples.isEmpty ? 0 : bgSamples[global % bgSamples.count]
                mixed[offset] = ReactionAudioMixer.mixSample(
                    mic: mic,
                    bg: bg,
                    bgVolume: input.bgVolume,
                    gain: gains[index],
                    muted: input.micMuted
                )
            }
            let pts = CMTimeAdd(micStart, CMTime(value: CMTimeValue(index * frames), timescale: CMTimeScale(Self.sampleRate)))
            if let buffer = PCMSampleBufferFactory.makeBuffer(samples: mixed, presentationTime: pts, format: pcmFormat) {
                try waitReady(audioInput)
                audioInput.append(buffer)
            }
            onProgress?(0.95 + 0.05 * Double(index + 1) / Double(max(chunkCount, 1)))
        }
    }

    /// Bounded wait for writer readiness — a stalled writer throws instead of
    /// hanging the job forever.
    private func waitReady(_ input: AVAssetWriterInput) throws {
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData {
            try checkCancelled()
            guard Date() < deadline else { throw ReactionExportError.writerSetup("writer stalled") }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    // MARK: - Helpers (workQueue)

    /// Drains one audio track to mono float samples with its start time.
    private func readMonoSamples(
        asset: AVURLAsset,
        track: AVAssetTrack,
        failure: ReactionExportError
    ) throws -> (samples: [Float], start: CMTime) {
        let reader = try makeReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: Self.pcmOutputSettings)
        guard reader.canAdd(output) else { throw failure }
        reader.add(output)
        guard reader.startReading() else { throw failure }
        register(reader: reader)
        var samples: [Float] = []
        var start = CMTime.zero
        var started = false
        while let sample = reader.output() {
            try checkCancelled()
            guard let floats = Self.floatSamples(of: sample) else { continue }
            if !started {
                start = CMSampleBufferGetPresentationTimeStamp(sample)
                started = true
            }
            samples.append(contentsOf: floats)
        }
        if reader.status == .failed {
            throw failure
        }
        return (samples, start)
    }

    private func checkCancelled() throws {
        stateLock.lock()
        let stop = cancelled
        stateLock.unlock()
        if stop {
            throw CancellationError()
        }
    }

    private func register(reader: AVAssetReader) {
        stateLock.lock()
        readerRefs.append(reader)
        stateLock.unlock()
    }

    private func makeReader(asset: AVURLAsset) throws -> AVAssetReader {
        do {
            return try AVAssetReader(asset: asset)
        } catch {
            throw ReactionExportError.unreadableRaw
        }
    }

    private func finish(writer: AVAssetWriter) -> Error? {
        var result: Error?
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            if writer.status != .completed {
                result = writer.error ?? ReactionExportError.writerSetup("unknown encode failure")
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private static func solidColor(_ color: CIColor) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    static func pcmFormat() -> CMFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
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
        ) == noErr else { return nil }
        return format
    }

    static var pcmOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// Float mono samples from a PCM sample buffer.
    ///
    /// Reads the data block directly instead of
    /// `CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer`: the block
    /// layout for our float32 PCM is just frames × channels, while the
    /// variable-length `AudioBufferList` dance proved unreliable across runs.
    /// Multi-channel interleaved audio is averaged down to mono.
    static func floatSamples(of sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee,
              asbd.mBitsPerChannel == 32,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer)
        else { return nil }
        let channels: Int
        if (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0 {
            channels = Int(asbd.mChannelsPerFrame)
        } else {
            // Non-interleaved multi-buffer layouts never occur in our pipeline
            // (readers request interleaved); refuse rather than misread.
            guard asbd.mChannelsPerFrame <= 1 else { return nil }
            channels = 1
        }
        guard channels >= 1 else { return nil }
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &pointer
        ) == kCMBlockBufferNoErr,
            let base = pointer, length > 0
        else { return nil }
        let frames = length / (MemoryLayout<Float>.size * channels)
        guard frames > 0 else { return nil }
        let floats = UnsafeBufferPointer(
            start: UnsafeRawPointer(base).assumingMemoryBound(to: Float.self),
            count: frames * channels
        )
        if channels == 1 {
            return Array(floats)
        }
        var mono = [Float](repeating: 0, count: frames)
        for index in 0 ..< frames {
            var sum: Float = 0
            for channel in 0 ..< channels {
                sum += floats[index * channels + channel]
            }
            mono[index] = sum / Float(channels)
        }
        return mono
    }
}
