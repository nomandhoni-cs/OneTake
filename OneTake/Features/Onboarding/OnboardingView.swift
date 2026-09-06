//
//  OnboardingView.swift
//  OneTake
//
//  Owns: First-launch onboarding — splash brand moment, three quick pages,
//  and a camera/mic permission step with rationale.
//  Why: HIG onboarding (fast, fun, optional, never blocks): splash opens the
//  flow, each page teaches one thing, Skip is always available, the flag
//  persists so it never reappears, and Profile offers a replay entry point.
//  See: docs/ARCHITECTURE.md §3 + AGENTS.md §4
//
import AVFoundation
import SwiftUI

/// First-launch gate lives in `ContentView` (`@AppStorage hasSeenOnboarding`).
struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding")
    private var hasSeenOnboarding = false
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { hasSeenOnboarding = true }
                    .accessibilityLabel("Skip onboarding")
            }
            .padding(.horizontal)
            .padding(.top, 8)

            TabView(selection: $page) {
                OnboardingSplashPage()
                    .tag(0)
                OnboardingPage(
                    icon: "doc.text.fill",
                    title: "Write your script",
                    bodyText: "Draft in the Scripts tab — or freestyle. Nothing to memorize before you roll."
                )
                .tag(1)
                OnboardingPage(
                    icon: "video.fill",
                    title: "Read, react, record",
                    bodyText: "The prompter scrolls by the lens. React over any clip, then trim and share from My Takes."
                )
                .tag(2)
                OnboardingPermissionPage()
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .accessibilityLabel("Onboarding pages")

            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 32)
                .accessibilityLabel(primaryTitle)
        }
    }

    private var primaryTitle: String {
        switch page {
        case 0: "Continue"
        case 1, 2: "Next"
        default: "Get Started"
        }
    }

    private func primaryAction() {
        if page < 3 {
            withAnimation { page += 1 }
        } else {
            hasSeenOnboarding = true
        }
    }
}

/// Splash brand moment — opens the flow, pure branding, one glance.
private struct OnboardingSplashPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "video.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.appAccent)
                .accessibilityHidden(true)
            Text("OneTake")
                .font(.largeTitle.weight(.bold))
            Text("Nail it in one take.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }
}

/// One idea per page — icon, title, single body line.
private struct OnboardingPage: View {
    var icon: String
    var title: String
    var bodyText: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(Color.appAccent)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.bold))
            Text(bodyText)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }
}

/// Permission step with rationale — enables, never blocks.
private struct OnboardingPermissionPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.appAccent)
                .accessibilityHidden(true)
            Text("Enable camera & mic")
                .font(.title.weight(.bold))
            Text("OneTake needs both to record. You can change this anytime in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("Enable Camera & Mic") {
                Task { await requestPermissions() }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Enable Camera and Mic")
            Spacer()
        }
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }

    private func requestPermissions() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }
}

#Preview {
    OnboardingView()
}
