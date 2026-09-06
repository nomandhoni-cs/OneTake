import CoreMedia
import Foundation
@testable import OneTake
import Testing

struct ReactionAudioMixerTests {
    // MARK: - Ducking curve

    @Test func attackReachesFullDuckInTime() {
        var ducking = ReactionDucking(duckedGain: 0.3, attack: 0.15, release: 0.8)
        let first = ducking.update(speaking: true, dt: 0.05)
        #expect(abs(first - 0.767) < 0.01)
        _ = ducking.update(speaking: true, dt: 0.05)
        let third = ducking.update(speaking: true, dt: 0.05)
        #expect(abs(third - 0.3) < 0.001)
        // Holds while speech continues.
        #expect(ducking.update(speaking: true, dt: 1.0) == 0.3)
    }

    @Test func releaseRestoresVolumeSmoothly() {
        var ducking = ReactionDucking(duckedGain: 0.3, attack: 0.15, release: 0.8)
        _ = ducking.update(speaking: true, dt: 1.0)
        #expect(ducking.gain == 0.3)
        let mid = ducking.update(speaking: false, dt: 0.4)
        #expect(abs(mid - 0.65) < 0.01)
        let end = ducking.update(speaking: false, dt: 0.4)
        #expect(end == 1.0)
    }

    @Test func silenceNeverDucks() {
        var ducking = ReactionDucking()
        #expect(ducking.update(speaking: false, dt: 5.0) == 1.0)
    }

    // MARK: - Sample mix

    @Test func mixClampsAndMutes() {
        #expect(ReactionAudioMixer.mixSample(mic: 0.9, bg: 0.9, bgVolume: 1, gain: 1, muted: false) == 1.0)
        #expect(ReactionAudioMixer.mixSample(mic: -0.9, bg: -0.9, bgVolume: 1, gain: 1, muted: false) == -1.0)
        // Muted mic contributes nothing; BG meter path is independent.
        #expect(ReactionAudioMixer.mixSample(mic: 0.8, bg: 0.5, bgVolume: 0.4, gain: 1, muted: true) == 0.2)
        // Ducked gain scales the BG term.
        #expect(abs(ReactionAudioMixer.mixSample(mic: 0, bg: 1, bgVolume: 0.4, gain: 0.3, muted: false) - 0.12) < 0.001)
    }

    // MARK: - VAD

    @Test func vadThresholds() {
        #expect(ReactionVAD.rmsDB(of: []) == -60)
        #expect(ReactionVAD.rmsDB(of: [Float](repeating: 0, count: 100)) == -60)
        let loud = ReactionVAD.rmsDB(of: [Float](repeating: 0.5, count: 100))
        #expect(loud > ReactionVAD.speechThresholdDB)
        let quiet = ReactionVAD.rmsDB(of: [Float](repeating: 0.001, count: 100))
        #expect(quiet < ReactionVAD.speechThresholdDB)
    }

    // MARK: - Chunker

    @Test func chunkerVendsFixedChunksWithTime() {
        var chunker = PCMChunker(chunkFrames: 1024, sampleRate: 44100)
        chunker.append([Float](repeating: 0.1, count: 600), time: CMTime(seconds: 1, preferredTimescale: 600))
        let empty = chunker.nextChunk()
        #expect(empty == nil)
        chunker.append([Float](repeating: 0.2, count: 500), time: CMTime(seconds: 2, preferredTimescale: 600))
        let chunkOpt = chunker.nextChunk()
        let chunk = try? #require(chunkOpt)
        #expect(chunk?.samples.count == 1024)
        #expect(abs((chunk?.time.seconds ?? -1) - 1) < 0.001)
        let drained = chunker.nextChunk()
        #expect(drained == nil)
        #expect(chunker.bufferedFrames == 76)
    }

    // MARK: - Mixer façade

    @Test @MainActor func mixerMirrorsReportsAndMutesMicOnly() {
        let mixer = ReactionAudioMixer()
        mixer.bgVolume = 0.5
        mixer.applyReport(micDB: -10, bgDB: -20, gain: 0.3)
        #expect(mixer.micMeterDB == -10)
        #expect(mixer.bgMeterDB == -20)
        #expect(mixer.liveBGVolume == 0.15)
        mixer.micMuted = true
        mixer.applyReport(micDB: -10, bgDB: -20, gain: 1)
        // Mic mute floors the mic meter but never touches the BG meter.
        #expect(mixer.micMeterDB == -60)
        #expect(mixer.bgMeterDB == -20)
    }
}
