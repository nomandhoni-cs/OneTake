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
    @Environment(\.dismiss)
    private var dismiss
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
    /// Reaction mode: fixed 1080p30 SDR pipeline — hides format/HDR/aspect.
    var isReaction = false
    /// Reaction controls bundle — nil hides the Cutout/Audio sections.
    /// Ranked by usefulness: cutout framing first, audio second, then notes.
    var reaction: ReactionSheetBindings?

    var body: some View {
        NavigationStack {
            List {
                if isRecordingOrPaused {
                    Section {
                        Label("Stop recording to change camera format", systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                if !isReaction {
                    Section("Camera") {
                        cameraSectionContent
                    }
                }
                if isReaction, let reaction {
                    ReactionCutoutSection(bindings: reaction)
                    ReactionAudioSection(mixer: reaction.mixer)
                }
                Section(isReaction ? "Reaction Notes" : "Teleprompter") {
                    TweakTrayView(speed: $speed, fontSize: $fontSize, opacity: $opacity) {}
                }
                if isReaction {
                    Section("Camera") {
                        cameraSectionContent
                    }
                } else {
                    Section("Aspect") {
                        AspectPickerView(ratio: $aspect)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var cameraSectionContent: some View {
        if isReaction {
            Label("1080p30 SDR in Reaction v1", systemImage: "video.fill")
            Text("Reaction composites record in SDR with a fixed 1080p canvas.")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
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
        }
        Toggle("Mirror", isOn: $mirrorMode)
        Toggle("Countdown", isOn: $countdownEnabled)
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

/// Bundled reaction controls for the settings sheet — one optional param keeps
/// the teleprompter call site untouched.
struct ReactionSheetBindings {
    var layout: Binding<ReactionLayout>
    var outline: Binding<ReactionOutline>
    var rect: Binding<CGRect>
    var mixer: ReactionAudioMixer
}

/// Cutout framing controls, ranked first — layout, position grid, outline.
private struct ReactionCutoutSection: View {
    var bindings: ReactionSheetBindings

    var body: some View {
        Section("Cutout") {
            Picker("Layout", selection: bindings.layout) {
                ForEach(ReactionLayout.allCases) { mode in
                    Label(mode.title, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Cutout layout")

            HStack(spacing: 8) {
                Text("Outline")
                Spacer()
                ForEach(ReactionOutline.allCases) { option in
                    Button {
                        bindings.outline.wrappedValue = option
                    } label: {
                        ZStack {
                            Circle()
                                .fill(option.color ?? Color.clear)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: option.color == nil ? 2 : 0))
                            if option.color == nil {
                                Image(systemName: "slash.circle").font(.caption).foregroundStyle(.secondary)
                            }
                            if bindings.outline.wrappedValue == option {
                                Circle().strokeBorder(Color.accentColor, lineWidth: 3).frame(width: 36, height: 36)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                    }
                    .accessibilityLabel("Outline \(option.title)")
                }
            }
        }

        Section {
            PresenterPositionGrid(rect: bindings.rect)
        } header: {
            Text("Presenter Position")
        } footer: {
            Text("Snaps the cutout frame; applies to Circle PiP. Drag the preview anytime for free placement.")
        }
    }
}

/// Spatial 3×3 grid — each cell sits where the presenter will, so placement
/// reads at a glance instead of as a text list.
private struct PresenterPositionGrid: View {
    @Binding var rect: CGRect

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(PresenterPosition.allCases) { position in
                let selected = PresenterPosition.matching(rect) == position
                Button {
                    rect = position.rect(for: rect.size)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: position.iconName)
                            .font(.title3)
                        Text(position.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .foregroundStyle(selected ? .white : .primary)
                    .background(
                        selected ? Color.accentColor : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Move presenter \(position.title.lowercased())")
            }
        }
        .padding(.vertical, 4)
    }
}

/// Audio controls, ranked second — live mic meter plus export mix settings.
private struct ReactionAudioSection: View {
    @Bindable var mixer: ReactionAudioMixer

    var body: some View {
        Section("Audio") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mic").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                VUMeterView(level: mixer.micMeterDB)
            }
            HStack {
                Text("Background volume")
                Spacer()
                Text("\(Int((mixer.bgVolume * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $mixer.bgVolume, in: 0 ... 1)
                .accessibilityLabel("Background volume")
            Toggle("Voice ducking", isOn: $mixer.duckEnabled)
            Toggle("Microphone", isOn: Binding(
                get: { !mixer.micMuted },
                set: { mixer.micMuted = !$0 }
            ))
            Text("For best sound, use headphones to keep background audio out of the mic.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
