//
//  AudioSessionService.swift
//  OneTake
//

import AVFoundation
import Combine
import Observation

@Observable
@MainActor
final class AudioSessionService: NSObject {
    private(set) var currentRouteName: String = "iPhone Microphone"
    private(set) var level: Float = -60 // dBFS floor
    private var isMonitoring = false
    private var recorder: AVAudioRecorder?
    private nonisolated(unsafe) var meterTimer: Timer?

    override init() {
        super.init()
        configureSession()
        observeRouteChanges()
        updateRouteName()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        meterTimer?.invalidate()
    }

    func configureSession() {
        #if targetEnvironment(simulator)
            currentRouteName = "Simulator Microphone"
        #else
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(
                    .playAndRecord,
                    mode: .videoRecording,
                    options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
                )
                try session.setActive(true)
            } catch {
                debugPrint("[AudioSessionService] configure failed: \(error)")
            }
        #endif
    }

    // MARK: - Route

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    // swiftlint:disable:next attributes
    @objc private func handleRouteChange(_ notification: Notification) {
        Task { @MainActor in
            self.updateRouteName()
        }
    }

    private func updateRouteName() {
        #if targetEnvironment(simulator)
            currentRouteName = "Simulator Microphone"
        #else
            let session = AVAudioSession.sharedInstance()
            if let input = session.currentRoute.inputs.first {
                let name = input.portName
                // Friendly mapping
                if input.portType == .bluetoothHFP || input.portType == .bluetoothA2DP {
                    currentRouteName = name.isEmpty ? "Bluetooth Mic" : name
                } else if input.portType == .headsetMic || input.portType == .headsetBT {
                    currentRouteName = name.isEmpty ? "Wired Headset" : name
                } else if input.portType == .usbAudio {
                    currentRouteName = name.isEmpty ? "USB Mic" : name
                } else {
                    currentRouteName = name.isEmpty ? "iPhone Microphone" : name
                }
            } else {
                currentRouteName = "iPhone Microphone"
            }
        #endif
    }

    // MARK: - VU Metering (via AVAudioRecorder metering)

    func startMetering() {
        guard !isMonitoring else { return }
        isMonitoring = true
        #if targetEnvironment(simulator)
            // Simulate level
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.level = Float.random(in: -45 ... -6)
                }
            }
        #else
            // Use recorder metering without actually recording to file
            let url = URL(fileURLWithPath: "/dev/null")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
            ]
            do {
                recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder?.isMeteringEnabled = true
                recorder?.record()
                meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let r = self.recorder else { return }
                        r.updateMeters()
                        let db = r.averagePower(forChannel: 0) // -160..0
                        self.level = max(-60, db)
                    }
                }
            } catch {
                debugPrint("[AudioSessionService] metering failed: \(error)")
            }
        #endif
    }

    func stopMetering() {
        isMonitoring = false
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        level = -60
    }

    var normalizedLevel: Float {
        // Map -60..0 dBFS to 0..1
        max(0, (level + 60) / 60)
    }

    var isClipping: Bool {
        level > -1
    }
}
