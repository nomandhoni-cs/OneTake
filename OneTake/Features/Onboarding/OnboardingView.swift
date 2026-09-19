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
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcomePage
                case .terms: TermsView(mode: .accept(onAgree: agreeToLegal))
                case .paywall: PaywallView(onUnlocked: { advance(from: .paywall) })
                case .permissions: permissionsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            // Toolbar, not a hand-rolled HStack: the system owns placement,
            // hit target, and Liquid Glass chrome on iOS 26.
            .toolbar {
                if step == .permissions {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { advance(from: .permissions) }
                            .accessibilityLabel("Skip this step")
                    }
                }
            }
            // `safeAreaInset` is the native way to pin an action: scrollable
            // pages (terms, paywall) get their content inset automatically
            // instead of hiding behind the button.
            .safeAreaInset(edge: .bottom) {
                OnboardingActionBar(step: step, onAgree: agreeToLegal, onAdvance: advance, onFinish: finish)
            }
        }
    }

    // MARK: - Pages

    /// Scrollable so the value props survive the largest Dynamic Type sizes
    /// instead of clipping against the pinned action.
    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 16) {
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
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var permissionsPage: some View {
        ScrollView {
            VStack(spacing: 16) {
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
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
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

/// The pinned primary action for each onboarding step.
///
/// A struct, not a helper func, so SwiftUI keeps identity across step changes
/// (see `.swiftlint.yml` `avoid_helper_func_view`). Carries a `.bar` material
/// because terms and paywall scroll underneath it — that is a system material
/// that adapts to light/dark and Liquid Glass, not a fixed colour.
private struct OnboardingActionBar: View {
    let step: OnboardingStep
    let onAgree: () -> Void
    let onAdvance: (OnboardingStep) -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            switch step {
            case .welcome:
                OnboardingPrimaryButton(title: "Continue") { onAdvance(.welcome) }
                    .accessibilityLabel("Continue")

            case .terms:
                // Consent line sits with the action it explains.
                Text("By tapping Agree, you accept our Terms and Privacy Policy.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("By tapping Agree, you accept our Terms and Privacy Policy.")
                OnboardingPrimaryButton(title: "Agree & Continue", action: onAgree)
                    .accessibilityLabel("Agree to Terms and Privacy Policy")
                    .accessibilityHint("Accepts Terms and Privacy and continues")

            case .paywall:
                // Plain button: declining must never compete with the purchase
                // CTA inside the paywall itself.
                Button("Not Now") { onAdvance(.paywall) }
                    .accessibilityLabel("Skip subscription for now")

            case .permissions:
                OnboardingPrimaryButton(title: "Get Started", action: onFinish)
                    .accessibilityLabel("Finish onboarding")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

/// The one prominent, full-width action per onboarding step. A struct rather
/// than a helper func so SwiftUI diffs it by identity (`avoid_helper_func_view`).
private struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
    }
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
