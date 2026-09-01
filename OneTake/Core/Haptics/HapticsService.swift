//
//  HapticsService.swift
//  OneTake
//

import CoreHaptics
import Foundation
import UIKit

@MainActor
final class HapticsService {
    private var engine: CHHapticEngine?
    private var supportsHaptics = false

    init() {
        #if !targetEnvironment(simulator)
            supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
            if supportsHaptics {
                prepareEngine()
            }
        #endif
    }

    private func prepareEngine() {
        do {
            engine = try CHHapticEngine()
            engine?.resetHandler = { [weak self] in
                // Attempt to restart on reset
                try? self?.engine?.start()
            }
            engine?.stoppedHandler = { reason in
                debugPrint("[Haptics] stopped: \(reason)")
            }
            try engine?.start()
        } catch {
            debugPrint("[Haptics] engine start failed: \(error)")
            engine = nil
            supportsHaptics = false
        }
    }

    func prewarm() {
        #if !targetEnvironment(simulator)
            if engine == nil, CHHapticEngine.capabilitiesForHardware().supportsHaptics {
                prepareEngine()
            } else {
                try? engine?.start()
            }
        #endif
    }

    // MARK: - Countdown pattern: 3, 2 transient; GO continuous burst

    func playCountdownTick(isFinal: Bool = false) {
        #if targetEnvironment(simulator)
            // Fallback only on simulator
            if isFinal {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            return
        #endif

        if supportsHaptics, let engine {
            do {
                if isFinal {
                    // Intense continuous burst 0.3s
                    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                    let event = CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [intensity, sharpness],
                        relativeTime: 0,
                        duration: 0.3
                    )
                    let pattern = try CHHapticPattern(events: [event], parameters: [])
                    let player = try engine.makePlayer(with: pattern)
                    try player.start(atTime: 0)
                } else {
                    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.65)
                    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
                    let pattern = try CHHapticPattern(events: [event], parameters: [])
                    let player = try engine.makePlayer(with: pattern)
                    try player.start(atTime: 0)
                }
            } catch {
                debugPrint("[Haptics] play failed, fallback: \(error)")
                fallbackTick(isFinal: isFinal)
            }
        } else {
            fallbackTick(isFinal: isFinal)
        }
    }

    private func fallbackTick(isFinal: Bool) {
        if isFinal {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
