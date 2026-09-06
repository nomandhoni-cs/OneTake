//  See: docs/ARCHITECTURE.md §6 (Review/Trim) + openspec/specs/trim-color-export/spec.md
import AVFoundation
import SwiftUI

struct TrimScrubberView: View {
    var duration: Double // seconds
    @Binding var startSeconds: Double
    @Binding var endSeconds: Double // inclusive end
    /// UI-trim-clipped source ranges to render (caller clips via
    /// `rangesClippedTo`). Gaps between ranges render as empty track —
    /// deleted footage is visibly gone, not silently kept.
    var segments: [BladeSegment] = []
    var selectedSegment: Int?
    var playheadSeconds: Double?
    var onBlade: (() -> Void)?
    var onDeleteSegment: (() -> Void)?
    var onSelectSegment: ((Int) -> Void)?

    private let minDuration: Double = 1.0

    /// Internal boundaries between adjacent spans (divider positions).
    private var dividers: [Double] {
        segments.sorted { $0.start < $1.start }.dropFirst().map(\.start)
    }

    private var orderedSegments: [BladeSegment] {
        segments.sorted { $0.start < $1.start }
    }

    private var isBladeDisabled: Bool {
        guard let onBlade else { return true }
        // If playhead provided, disable at ends; otherwise enable when more than 1s range
        if let playhead = playheadSeconds {
            return playhead <= startSeconds + 0.1 || playhead >= endSeconds - 0.1
        }
        return (endSeconds - startSeconds) < 1.1
    }

    private var isDeleteDisabled: Bool {
        guard onDeleteSegment != nil else { return true }
        guard let sel = selectedSegment else { return true }
        return orderedSegments.count <= 1 || sel < 0 || sel >= orderedSegments.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let startX = CGFloat(startSeconds / duration) * w
                let endX = CGFloat(endSeconds / duration) * w
                let selectedW = max(0, endX - startX)

                ZStack(alignment: .leading) {
                    // Track
                    Capsule().fill(Color.white.opacity(0.18)).frame(height: 44)

                    // Selected range
                    Capsule()
                        .fill(Color.blue.opacity(0.55))
                        .frame(width: selectedW, height: 44)
                        .offset(x: startX)

                    // Surviving spans at source positions; deleted gaps stay empty.
                    ForEach(Array(orderedSegments.enumerated()), id: \.offset) { idx, seg in
                        let segX = CGFloat(seg.start / duration) * w
                        let segW = CGFloat(seg.duration / duration) * w
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.1))
                                .strokeBorder(selectedSegment == idx ? Color.yellow : Color.clear, lineWidth: 2)
                            if segW > 48 {
                                Text(format(seconds: seg.duration))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .frame(width: segW, height: 44)
                        .offset(x: segX)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectSegment?(idx) }
                    }

                    // Blade cut dividers at internal boundaries
                    ForEach(dividers, id: \.self) { cut in
                        let x = CGFloat(cut / duration) * w
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: 44)
                            .offset(x: x - 1)
                            .shadow(color: .black.opacity(0.35), radius: 2)
                    }

                    // Playhead, clamped clear of both trim handles
                    if let playhead = playheadSeconds {
                        let rawX = CGFloat(playhead / duration) * w
                        let lower = min(startX + 13, endX)
                        let upper = max(endX - 13, startX)
                        let px = min(max(rawX, lower), upper)
                        Rectangle().fill(Color.yellow).frame(width: 2, height: 44).offset(x: px - 1)
                    }

                    // Handles
                    TrimHandle()
                        .offset(x: startX - 12)
                        .gesture(
                            DragGesture()
                                .onChanged { g in
                                    var s = Double(g.location.x / w) * duration
                                    s = min(max(0, s), endSeconds - minDuration)
                                    startSeconds = s
                                }
                        )
                    TrimHandle()
                        .offset(x: endX - 12)
                        .gesture(
                            DragGesture()
                                .onChanged { g in
                                    var e = Double(g.location.x / w) * duration
                                    e = max(min(duration, e), startSeconds + minDuration)
                                    endSeconds = e
                                }
                        )
                }
            }
            .frame(height: 44)

            HStack {
                Text(format(seconds: startSeconds)).font(.caption.monospacedDigit())
                Spacer()
                Text("Trim: \(format(seconds: endSeconds - startSeconds))").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(format(seconds: endSeconds)).font(.caption.monospacedDigit())
            }

            // Blade controls
            if onBlade != nil || onDeleteSegment != nil {
                HStack(spacing: 10) {
                    if let onBlade {
                        Button(action: onBlade) {
                            Label("Blade", systemImage: "scissors")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBladeDisabled)
                    }
                    if let onDeleteSegment {
                        Button(role: .destructive, action: onDeleteSegment) {
                            Label("Delete Segment", systemImage: "trash")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isDeleteDisabled)
                    }
                    Spacer()
                    if let sel = selectedSegment, sel < orderedSegments.count {
                        Text("Segment \(sel + 1)/\(orderedSegments.count) • \(format(seconds: orderedSegments[sel].duration))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            startSeconds = max(0, min(startSeconds, duration - minDuration))
            endSeconds = min(duration, max(endSeconds, startSeconds + minDuration))
        }
    }

    private func format(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct TrimHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white)
            .frame(width: 24, height: 44)
            .shadow(color: .black.opacity(0.25), radius: 4)
            .overlay(
                VStack(spacing: 3) {
                    ForEach(0 ..< 3, id: \.self) { _ in Capsule().fill(Color.black.opacity(0.25)).frame(width: 2, height: 14) }
                }
            )
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var s = 2.0
        @Previewable @State var e = 28.0
        TrimScrubberView(
            duration: 30,
            startSeconds: $s,
            endSeconds: $e,
            segments: [BladeSegment(start: 2, duration: 6), BladeSegment(start: 8, duration: 7), BladeSegment(start: 15, duration: 13)],
            selectedSegment: 1,
            playheadSeconds: 10,
            onBlade: {},
            onDeleteSegment: {},
            onSelectSegment: { _ in }
        )
        .padding()
        .background(Color.black)
    }
#endif
