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
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init() {
        state = ProcessInfo.processInfo.thermalState
        shouldDowngrade = (state == .critical)
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.state = ProcessInfo.processInfo.thermalState
                self.shouldDowngrade = (self.state == .critical)
                if self.shouldDowngrade {
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
