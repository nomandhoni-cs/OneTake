//
//  OnboardingView.swift
//  OneTake
//
//  Owns: First-run decision flow — welcome, terms, trial offer, explainer.
//  Why: v2 is gates, not a tutorial: every step resolves a decision (start,
//  agree, subscribe-or-skip, understand). Versioned so future legal bumps can
//  force a terms-only pass; system permission prompts stay in context (§15).
//  See: openspec/specs/onboarding-v2/spec.md
//
import SwiftUI

/// Onboarding steps in order. Terms is the only non-skippable step.
enum OnboardingStep: Int, CaseIterable {
    case welcome, terms, paywall, permissions
}

/// Pure flow logic — unit-tested, no SwiftUI dependency.
enum OnboardingFlow {
    static let currentVersion = 2

    static func needsOnboarding(completedVersion: Int, acceptedLegalVersion: Int) -> Bool {
        completedVersion < currentVersion || acceptedLegalVersion < LegalDocuments.currentVersion
    }

    /// Fresh users start at welcome; returning users with stale legal go to terms.
    static func startStep(completedVersion: Int, acceptedLegalVersion: Int) -> OnboardingStep {
        completedVersion < currentVersion ? .welcome : .terms
    }

    static func canSkip(_ step: OnboardingStep) -> Bool {
        step == .paywall || step == .permissions
    }
}

/// Versioned first-run flow. Owns its step state; completion persists twice
/// (flow version + legal version/timestamp) for future legal bumps.
/// `startStep`/`onFinish` make it replayable (e.g. Profile tour) without
/// touching gate semantics — replaying an already-current flow is a no-op.
struct OnboardingView: View {
    @Environment(ProEntitlementService.self)
    private var pro
    @AppStorage("completedOnboardingVersion")
    private var completedVersion = 0
    @AppStorage("acceptedLegalVersion")
    private var acceptedLegalVersion = 0
    @AppStorage("acceptedLegalAt")
    private var acceptedLegalAt = ""

    @State private var step: OnboardingStep
    private let onFinish: (() -> Void)?

    init(startStep: OnboardingStep = .welcome, onFinish: (() -> Void)? = nil) {
        _step = State(initialValue: startStep)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if OnboardingFlow.canSkip(step) {
                    Button("Skip") { advance(from: step) }
                        .accessibilityLabel("Skip this step")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Plain switch, not a TabView: pages must not be swipe-skippable
            // (terms acceptance is legally binding).
            Group {
                switch step {
                case .welcome: welcomePage
                case .terms: TermsView(mode: .accept(onAgree: agreeToLegal))
                case .paywall: paywallPage
                case .permissions: permissionsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Onboarding")

            bottomBar
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "video.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.appAccent)
                .accessibilityHidden(true)
            Text("OneTake")
                .font(.largeTitle.weight(.bold))
            VStack(alignment: .leading, spacing: 10) {
                ValueRow(icon: "doc.text.fill", text: "Write scripts, read them off the lens")
                ValueRow(icon: "person.2.fill", text: "React over any clip, solo or together")
                ValueRow(icon: "wand.and.stars", text: "Trim, grade with 10 LUTs, export in 4K")
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var paywallPage: some View {
        NavigationStack {
            PaywallView(onUnlocked: { advance(from: .paywall) })
        }
    }

    private var permissionsPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.appAccent)
                .accessibilityHidden(true)
            Text("Private by design")
                .font(.title.weight(.bold))
            Text("Everything stays on your device. You'll be asked for access exactly when each feature needs it — never before.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                ValueRow(icon: "camera.fill", text: "Camera & microphone — when you first record")
                ValueRow(icon: "photo.fill", text: "Photo library — when you first save a take")
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Fixed bottom bar (HIG: primary action never scrolls away)

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(step == .terms ? 1 : 0)
            Group {
                switch step {
                case .welcome:
                    Button("Continue") { advance(from: .welcome) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .accessibilityLabel("Continue")
                case .terms:
                    termsBottomBar
                case .paywall:
                    Button("Not Now") { advance(from: .paywall) }
                        .font(.subheadline)
                        .padding(.vertical, 12)
                        .accessibilityLabel("Skip subscription for now")
                case .permissions:
                    Button("Get Started") { finish() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .accessibilityLabel("Finish onboarding")
                }
            }
            .background(.bar)
        }
        // Keep bar out of the safe area's bottom edge.
        .padding(.bottom, 8)
    }

    private var termsBottomBar: some View {
        VStack(spacing: 8) {
            // Consent line — reassures that tapping View opens the full sheet.
            Text("By tapping Agree, you accept our Terms and Privacy Policy.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .accessibilityLabel("By tapping Agree, you accept our Terms and Privacy Policy.")
            Button("Agree & Continue") { agreeToLegal() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .accessibilityLabel("Agree to Terms and Privacy Policy")
                .accessibilityHint("Accepts Terms and Privacy and continues")
        }
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Flow

    private func agreeToLegal() {
        acceptedLegalVersion = LegalDocuments.currentVersion
        acceptedLegalAt = ISO8601DateFormatter().string(from: Date())
        advance(from: .terms)
    }

    private func advance(from current: OnboardingStep) {
        let order = OnboardingStep.allCases
        guard let index = order.firstIndex(of: current) else {
            finish()
            return
        }
        let next = index + 1
        if next < order.count {
            withAnimation { step = order[next] }
        } else {
            finish()
        }
    }

    private func finish() {
        completedVersion = OnboardingFlow.currentVersion
        onFinish?()
    }
}

#Preview {
    OnboardingView()
        .environment(ProEntitlementService.previewLocked)
}

/// Icon + one-line value prop — struct (not a helper func) for view identity.
private struct ValueRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text).font(.body)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.appAccent)
        }
        .accessibilityElement(children: .combine)
    }
}
