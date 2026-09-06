//
//  ReactionAudioMixer.swift
//  OneTake
//
//  Owns: Reaction audio DSP — voice-activity ducking, mic/BG meters, PCM
//  chunking, and mixed-buffer construction for `AVAssetWriter`.
//  Why: Pure DSP (`ReactionDucking`, `PCMChunker`) stays deterministic and
//  unit-testable; the `@Observable` mixer publishes meters for dual VU views.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/reaction-studio-cutout/specs/reaction-studio/spec.md
//
import AVFoundation
import Foundation
import Observation

/// Deterministic ducking curve — no audio APIs, fully unit-testable.
///
/// BG gain dives to `duckedGain` (30%) with a fast attack while speech is
/// present and glides back with a slow release afterwards.
struct ReactionDucking {
    /// Ducked BG multiplier (0.3 = −70%).
    var duckedGain: Float = 0.3
    /// Time to reach full duck (spec: fast, ~150ms).
    var attack: TimeInterval = 0.15
    /// Time to restore full volume (spec: smooth, ~800ms).
    var release: TimeInterval = 0.8

    private(set) var gain: Float = 1.0

    mutating func update(speaking: Bool, dt: TimeInterval) -> Float {
        let target: Float = speaking ? duckedGain : 1.0
        guard dt > 0 else {
            gain = target
            return gain
        }
        let span = 1 - duckedGain
        if target < gain {
            let rate = attack > 0 ? attack : 0.001
            gain = max(target, gain - span * Float(dt / rate))
        } else if target > gain {
            let rate = release > 0 ? release : 0.001
            gain = min(target, gain + span * Float(dt / rate))
        }
        return gain
    }

    mutating func reset() {
        gain = 1.0
    }
}

/// Fixed-size PCM chunker — accumulates timestamped mono samples and vends
/// exactly `chunkFrames` per call so mic/BG stay sample-aligned.
struct PCMChunker {
    let chunkFrames: Int
    let sampleRate: Double
    private var samples: [Float] = []
    private var startTime: CMTime?
    private var consumedFrames = 0

    init(chunkFrames: Int = 1024, sampleRate: Double = 44100) {
        self.chunkFrames = chunkFrames
        self.sampleRate = sampleRate
    }

    var bufferedFrames: Int {
        samples.count
    }

    mutating func append(_ new: [Float], time: CMTime) {
        if startTime == nil {
            startTime = time
        }
        samples.append(contentsOf: new)
    }

    mutating func nextChunk() -> (time: CMTime, samples: [Float])? {
        guard samples.count >= chunkFrames, let start = startTime else { return nil }
        let time = CMTimeAdd(start, CMTime(value: CMTimeValue(consumedFrames), timescale: CMTimeScale(sampleRate)))
        let chunk = Array(samples.prefix(chunkFrames))
        samples.removeFirst(chunkFrames)
        consumedFrames += chunkFrames
        if samples.isEmpty {
            startTime = nil
            consumedFrames = 0
        }
        return (time, chunk)
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        startTime = nil
        consumedFrames = 0
    }
}

/// Voice-activity threshold in dBFS (RMS). Above this the mic counts as speech.
enum ReactionVAD {
    static let speechThresholdDB: Float = -42

    static func rmsDB(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -60 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0.000_01 else { return -60 }
        return max(-60, 20 * log10(rms))
    }
}

/// Mix state published to the reaction UI (dual meters + live BG volume).
///
/// Threading: the encode pipeline owns its own `ReactionDucking` for the file
/// mix (single source of truth at chunk cadence) and reports
/// `(micDB, bgDB, gain)` back; this façade mirrors those reports for meters
/// and derives the live BG monitor volume. `mixSample` is the shared DSP.
@Observable
@MainActor
final class ReactionAudioMixer {
    /// User toggle — when off, BG follows the slider only.
    var duckEnabled = true
    /// User slider 0...1.
    var bgVolume: Float = 0.4
    /// User mic mute — mutes file + meter, never the BG meter.
    var micMuted = false

    private(set) var micMeterDB: Float = -60
    private(set) var bgMeterDB: Float = -60
    private(set) var appliedBGGain: Float = 1.0

    /// Live BG player volume (slider × ducking) — mirrors the file mix.
    var liveBGVolume: Float {
        bgVolume * appliedBGGain
    }

    /// Mirror a pipeline audio report for meters + monitor volume.
    func applyReport(micDB: Float, bgDB: Float, gain: Float) {
        micMeterDB = micMuted ? -60 : micDB
        bgMeterDB = bgDB
        appliedBGGain = gain
    }

    /// Live mic meter feed during capture (mute floors it, never the BG side).
    func setMicMeter(_ db: Float) {
        micMeterDB = micMuted ? -60 : db
    }

    /// Sample mix for the file: mic + ducked BG, soft-clamped.
    nonisolated static func mixSample(mic: Float, bg: Float, bgVolume: Float, gain: Float, muted: Bool) -> Float {
        let mixed = (muted ? 0 : mic) + bg * bgVolume * gain
        return min(1, max(-1, mixed))
    }

    func reset() {
        micMeterDB = -60
        bgMeterDB = -60
        appliedBGGain = 1.0
    }
}

/// Offline lookahead ducking — no audio APIs, fully unit-testable.
///
/// Unlike the causal `ReactionDucking.update` (which only sees the present),
/// this precomputes per-chunk gains over a speech-flag array with a future
/// horizon, so the BG is already ducking at the first voiced chunk. Used by
/// the post-capture export job where the whole envelope is known up front.
enum LookaheadDucker {
    /// Gains for each chunk. `lookaheadChunks` of future horizon anticipate
    /// speech; `chunkDuration` drives the attack/release ramps.
    static func gains(
        speaking: [Bool],
        ducking: ReactionDucking,
        lookaheadChunks: Int,
        chunkDuration: TimeInterval
    ) -> [Float] {
        var curve = ducking
        curve.reset()
        var out: [Float] = []
        out.reserveCapacity(speaking.count)
        for index in speaking.indices {
            let horizon = min(speaking.count, index + 1 + max(lookaheadChunks, 0))
            let anticipated = speaking[index ..< horizon].contains(true)
            out.append(curve.update(speaking: anticipated, dt: chunkDuration))
        }
        return out
    }
}

/// Builds `CMSampleBuffer`s from mixed PCM for `AVAssetWriterInput`.
enum PCMSampleBufferFactory {
    static func makeBuffer(
        samples: [Float],
        presentationTime: CMTime,
        format: CMFormatDescription
    ) -> CMSampleBuffer? {
        guard !samples.isEmpty else { return nil }
        var sampleBuffer: CMSampleBuffer?
        let length = samples.count * MemoryLayout<Float>.size
        let status = samples.withUnsafeBufferPointer { pointer -> OSStatus in
            guard let baseAddress = pointer.baseAddress else { return kCMBlockBufferNoErr }
            var blockBuffer: CMBlockBuffer?
            var status = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: length,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: length,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
            guard status == kCMBlockBufferNoErr, let blockBuffer else { return status }
            status = CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: length
            )
            guard status == kCMBlockBufferNoErr else { return status }
            return CMAudioSampleBufferCreateWithPacketDescriptions(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: format,
                sampleCount: samples.count,
                presentationTimeStamp: presentationTime,
                packetDescriptions: nil,
                sampleBufferOut: &sampleBuffer
            )
        }
        guard status == noErr else { return nil }
        return sampleBuffer
    }
}
