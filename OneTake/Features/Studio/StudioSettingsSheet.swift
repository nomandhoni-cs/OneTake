//
//  StudioSettingsSheet.swift
//  OneTake
//

import AVFoundation
import SwiftUI

///
///  StudioSettingsSheet.swift
///  OneTake
///
///  Bottom sheet for camera settings — presented via `.sheet(detents: [.medium, .large])`.
///  Disables format controls (res/fps/HDR) while recording/paused with banner.
///  Shares `TweakTrayView` state (speed/font/opacity) so dismiss does not lose values.
///  Best practices: `@Binding` for two-way, `disabled` + caption for unsupported combos.
///
struct StudioSettingsSheet: View {
    @Binding var resolution: Resolution
    @Binding var frameRate: FrameRate
    @Binding var enableHDR: Bool
    @Binding var mirrorMode: Bool
    @Binding var countdownEnabled: Bool
    @Binding var aspect: AspectRatio

    @Binding var speed: Double
    @Binding var fontSize: Double
    @Binding var opacity: Double

    var isRecordingOrPaused: Bool
    var supportedCombos: [(resolution: Resolution, frameRate: FrameRate, hdr: Bool)] = []

    var body: some View {
        NavigationStack {
            List {
                if isRecordingOrPaused {
                    Section {
                        Label("Stop recording to change camera format", systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                Section("Camera") {
                    Picker("Resolution", selection: $resolution) {
                        ForEach(Resolution.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .disabled(isRecordingOrPaused)

                    Picker("Frame Rate", selection: $frameRate) {
                        ForEach(FrameRate.allCases) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    .disabled(isRecordingOrPaused)

                    if !isComboSupported(resolution: resolution, frameRate: frameRate) {
                        Text("This resolution + frame rate is not supported on this device and will fall back to 1080p.")
                            .font(.caption2).foregroundStyle(.red)
                    }

                    Toggle("HDR / Dolby Vision", isOn: $enableHDR)
                        .disabled(isRecordingOrPaused || !isHDRSupported())
                    if !isHDRSupported() {
                        Text("HDR not supported for the current device/format.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Toggle("Mirror", isOn: $mirrorMode)
                    Toggle("Countdown", isOn: $countdownEnabled)
                }

                Section("Teleprompter") {
                    TweakTrayView(speed: $speed, fontSize: $fontSize, opacity: $opacity) {}
                }

                Section("Aspect") {
                    AspectPickerView(ratio: $aspect)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func isComboSupported(resolution: Resolution, frameRate: FrameRate) -> Bool {
        if supportedCombos.isEmpty {
            return true
        }
        return supportedCombos.contains { $0.resolution == resolution && $0.frameRate == frameRate }
    }

    private func isHDRSupported() -> Bool {
        if supportedCombos.isEmpty {
            return false
        }
        return supportedCombos.contains { $0.hdr }
    }
}

#Preview("Idle") {
    StudioSettingsSheet(
        resolution: .constant(.hd1080p),
        frameRate: .constant(.standard),
        enableHDR: .constant(false),
        mirrorMode: .constant(true),
        countdownEnabled: .constant(true),
        aspect: .constant(.wide),
        speed: .constant(2),
        fontSize: .constant(24),
        opacity: .constant(0.35),
        isRecordingOrPaused: false
    )
}

#Preview("Recording disabled") {
    StudioSettingsSheet(
        resolution: .constant(.uhd4K),
        frameRate: .constant(.smooth),
        enableHDR: .constant(true),
        mirrorMode: .constant(true),
        countdownEnabled: .constant(true),
        aspect: .constant(.wide),
        speed: .constant(2),
        fontSize: .constant(24),
        opacity: .constant(0.35),
        isRecordingOrPaused: true
    )
}
