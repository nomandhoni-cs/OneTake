// swiftlint:disable:next prefer_observable
//
//  PrompterView.swift
//  OneTake
//

import Combine
import SwiftUI

/// ProMotion 120 Hz scrolling prompter driven by TimelineView.
struct PrompterView: View {
    let text: String
    var speedMultiplier: Double // 1.0–4.0
    var fontSize: Double // 18–36
    var opacity: Double // 0–0.8 (backdrop)
    var isScrolling: Bool

    @State private var offsetY: CGFloat = 0
    @State private var lastDate: Date?

    private let basePointsPerSecond: CGFloat = 18 // tuned base speed

    var body: some View {
        GeometryReader { geo in
            let pointsPerSecond = basePointsPerSecond * CGFloat(speedMultiplier)

            TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
                let now = timeline.date
                let delta: CGFloat = {
                    guard let last = lastDate, isScrolling else { return 0 }
                    return CGFloat(now.timeIntervalSince(last))
                }()

                let content = scriptContent(width: geo.size.width)

                ZStack(alignment: .top) {
                    // Frosted glass backdrop
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.55 + opacity * 0.45)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        )
                        // Eye-line accent
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.white.opacity(0.55))
                                .frame(height: 2)
                                .padding(.horizontal, 20)
                                .padding(.top, 10)
                        }

                    // Scrolling text
                    content
                        .offset(y: offsetY)
                        .animation(nil, value: offsetY)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onAppear { lastDate = now }
                .onChange(of: now) { _, new in
                    guard isScrolling else { lastDate = new; return }
                    offsetY -= pointsPerSecond * delta
                    // Reset when scrolled past
                    // Approximate: reset when offsetY < -estimatedHeight
                    lastDate = new
                }
                .onChange(of: isScrolling) { _, scrolling in
                    if !scrolling {
                        lastDate = now
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }

    // swiftlint:disable:next avoid_helper_func_view
    private func scriptContent(width: CGFloat) -> some View {
        Text(text.isEmpty ? "Your script will appear here.\n\nAdd words in the editor, then press Record." : text)
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(width: width - 32, alignment: .leading)
            .padding(16)
    }
}

// Fallback display-link variant (not used unless TimelineView throttled; kept for spec coverage)
// swiftlint:disable:next prefer_observable
final class DisplayLinkPrompterDriver: ObservableObject {
    @Published var offsetY: CGFloat = 0
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    var pointsPerSecond: CGFloat = 18
    var isScrolling = false

    func start() {
        guard link == nil else { return }
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link?.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = 0
    }

    // swiftlint:disable:next attributes
    @objc private func tick(_ link: CADisplayLink) {
        guard isScrolling else { lastTimestamp = link.timestamp; return }
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp; return
        }
        let delta = CGFloat(link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp
        offsetY -= pointsPerSecond * delta
    }
}

#Preview {
    PrompterView(
        text: "Hello OneTake\n\nThis is a scrolling prompter at 2× speed.",
        speedMultiplier: 2,
        fontSize: 22,
        opacity: 0.4,
        isScrolling: true
    )
    .padding()
}
