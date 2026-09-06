//
//  ReactionStudioComponents.swift
//  OneTake
//
//  Owns: Reaction studio building blocks — badges, empty state,
//  pending banner, presenter gestures, cutout/audio/transport bars.
//  Why: Extracted from `ReactionStudioView` to keep both files under the
//  `file_length` lint budget; pure presentational structs with callbacks.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/capture-first-reaction-pipeline/specs/reaction-post-processing/spec.md
//
import SwiftUI

struct PausedBadge: View {
    var body: some View {
        VStack {
            Text("Paused").font(.headline).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.black.opacity(0.6), in: Capsule()).padding(.top, 80)
            Spacer()
        }
    }
}

struct BackgroundEmptyState: View {
    var onPick: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.7))
            Text("Pick a background to react to")
                .font(.headline)
                .foregroundStyle(.white)
            Button("BG Media", action: onPick)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Pick background media")
                .accessibilityHint("Opens the photo library to choose a video or photo")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35))
    }
}

struct PendingExportBanner: View {
    var onProcess: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text("Unprocessed recording")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Button("Process", action: onProcess)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Process pending recording")
            Button("Discard", role: .destructive, action: onDiscard)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Draggable + pinch-scalable presenter placement layer.
struct PresenterGestureLayer: View {
    @Binding var rect: CGRect
    var enabled: Bool

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard enabled else { return }
                            let size = geo.size
                            guard size.width > 0, size.height > 0 else { return }
                            var next = rect
                            next.origin.x += value.translation.width / size.width / 8
                            next.origin.y += value.translation.height / size.height / 8
                            rect = clamped(next)
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            guard enabled else { return }
                            var next = rect
                            let scale = max(0.5, min(2.0, value.magnification))
                            let cx = next.midX
                            let cy = next.midY
                            next.size.width = clampSide(rect.width * scale)
                            next.size.height = clampSide(rect.height * scale)
                            next.origin.x = cx - next.width / 2
                            next.origin.y = cy - next.height / 2
                            rect = clamped(next)
                        }
                )
        }
        .ignoresSafeArea()
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        CGRect(
            x: min(max(rect.origin.x, -0.2), 1.0),
            y: min(max(rect.origin.y, -0.2), 1.0),
            width: clampSide(rect.width),
            height: clampSide(rect.height)
        )
    }

    private func clampSide(_ value: CGFloat) -> CGFloat {
        min(max(value, ReactionPresenterDefaults.minSide), ReactionPresenterDefaults.maxSide)
    }
}

struct ReactionTransportBar: View {
    var isRecording: Bool
    var isPaused: Bool
    var elapsedSeconds: Int
    var hasBackground: Bool
    /// True while recording — Restart BG is preview-only (linear timeline).
    var bgLocked: Bool
    var onRestartBG: () -> Void
    var onRecord: () -> Void
    var onPause: () -> Void
    var onResume: () -> Void
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 16) {
                Button(action: onRestartBG) {
                    Label("Restart BG", systemImage: "backward.end.fill")
                        .font(.caption2.weight(.medium)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6).background(
                            Color.black.opacity(0.55),
                            in: Capsule()
                        )
                }
                .disabled(!hasBackground || bgLocked)
                .accessibilityLabel("Restart background")
                Spacer()
                if isPaused {
                    Button(action: onResume) {
                        ZStack {
                            Circle().fill(Color.green).frame(width: 68, height: 68)
                            Image(systemName: "play.fill").foregroundStyle(.white).font(.title2)
                        }.shadow(color: .black.opacity(0.3), radius: 8)
                    }.accessibilityLabel("Resume recording")
                    Button(action: onStop) {
                        ZStack {
                            Circle().fill(Color.red).frame(width: 68, height: 68)
                            RoundedRectangle(cornerRadius: 6).fill(Color.white).frame(width: 28, height: 28)
                        }.shadow(color: .black.opacity(0.3), radius: 8)
                    }.accessibilityLabel("Stop recording")
                } else if isRecording {
                    Button(action: onPause) {
                        ZStack {
                            Circle().fill(Color.white).frame(width: 68, height: 68)
                            HStack(spacing: 6) {
                                Rectangle().fill(Color.black).frame(width: 8, height: 28).clipShape(Capsule())
                                Rectangle().fill(Color.black).frame(width: 8, height: 28).clipShape(Capsule())
                            }
                        }.shadow(color: .black.opacity(0.3), radius: 8)
                    }.accessibilityLabel("Pause recording")
                    Button(action: onStop) {
                        ZStack {
                            Circle().fill(Color.red).frame(width: 68, height: 68)
                            RoundedRectangle(cornerRadius: 6).fill(Color.white).frame(width: 28, height: 28)
                        }.shadow(color: .black.opacity(0.3), radius: 8)
                    }.accessibilityLabel("Stop recording")
                } else {
                    Button(action: onRecord) {
                        ZStack {
                            Circle().fill(Color.white).frame(width: 68, height: 68)
                            Circle().fill(Color.red).frame(width: 58, height: 58)
                        }.shadow(color: .black.opacity(0.3), radius: 8)
                    }.accessibilityLabel("Start reaction recording")
                }
                Spacer()
                Text(isRecording ? format(seconds: elapsedSeconds) : "Ready")
                    .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 10).padding(
                        .vertical,
                        6
                    )
                    .background(Color.black.opacity(0.55), in: Capsule())
            }
            if bgLocked {
                Text("BG locked while recording — restart in preview.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private func format(seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
