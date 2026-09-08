//
//  ThermalMonitor.swift
//  OneTake
//

import Foundation
import Observation

@Observable
@MainActor
final class ThermalMonitor {
    var state: ProcessInfo.ThermalState = .nominal
    var shouldDowngrade = false
    /// Lifetime handle, not view state (`@ObservationIgnored`).
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        state = ProcessInfo.processInfo.thermalState
        shouldDowngrade = (state == .critical)
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let monitor = self else { return }
            Task { @MainActor in
                monitor.state = ProcessInfo.processInfo.thermalState
                monitor.shouldDowngrade = (monitor.state == .critical)
                if monitor.shouldDowngrade {
                    debugPrint("[Thermal] critical → suggest 1080p")
                }
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
