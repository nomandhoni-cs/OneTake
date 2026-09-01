//
//  RootTabView.swift
//  OneTake
//
//  Bottom navigation shell for OneTake.
//
//  ## Best-practices applied
//  - State: `@State` for local tab paths, `@SceneStorage` for
//    selected tab persistence, `@AppStorage` for last script. Keeps bodies pure.
//  - Concurrency: `.task` / `.onReceive` structured, no `onAppear` fire-and-forget.
//  - Rendering: Small extracted `struct` subviews (`ScriptsTab`, `StudioTab`)
//    so SwiftUI diffing skips unchanged branches; no type-erased wrapper.
//  - Safety: No force unwraps; `guard let` for script lookup.
//  - A11y: 44pt hit target per tab, labels/hints in HIG order.
//
//  See: docs/ARCHITECTURE.md §4 (Navigation) + AGENTS.md §4
import SwiftData
import SwiftUI

/// Tab identifiers for the bottom shell — keeps HIG ordering: My Takes → Scripts → Studio → Profile.
enum AppTab: String, CaseIterable {
    case takes, scripts, studio, profile
}

private extension AppTab {
    /// Display title for the pill.
    var title: String {
        switch self {
        case .takes: "My Takes"
        case .scripts: "Scripts"
        case .studio: "Studio"
        case .profile: "Profile"
        }
    }

    /// SF Symbol for the pill.
    var iconName: String {
        switch self {
        case .takes: "film.stack"
        case .scripts: "doc.text"
        case .studio: "video.fill"
        case .profile: "person.crop.circle"
        }
    }
}

/// Root tab shell — unified 4-tab TabView (My Takes / Scripts / Studio / Profile)
/// inside a single `sidebarAdaptable` Liquid Glass container. Studio is a
/// first-class tab, not an external overlay.
struct RootTabView: View {
    // MARK: - State (local UI, per best practices)

    /// Persists selected tab across launches.
    @SceneStorage("selectedTab")
    private var selectedTabRaw = AppTab.takes.rawValue
    /// Per-tab navigation stacks — stored here so switching tabs does not deallocate.
    @State private var takesPath = NavigationPath()
    @State private var scriptsPath = NavigationPath()
    @State private var studioPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    /// Last script used in Studio, for selector restoration.
    @AppStorage("lastScriptID")
    private var lastScriptID = ""
    /// Recording flag published by StudioView via AppStorage.
    @AppStorage("studioIsRecording")
    private var isStudioRecording = false
    @State private var pendingTab: AppTab?
    @State private var showLeaveConfirm = false

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { AppTab(rawValue: selectedTabRaw) ?? .takes },
            set: { newValue in selectedTabRaw = newValue.rawValue }
        )
    }

    // MARK: - Body (pure, lightweight — no heavy work)

    var body: some View {
        // Unified 4-tab TabView — Studio is now a first-class tab inside the
        // same Liquid Glass pill (sidebarAdaptable), not an external overlay.
        TabView(selection: selectedTab) {
            Tab("My Takes", systemImage: "film.stack", value: .takes) {
                MyTakesView()
            }
            Tab("Scripts", systemImage: "doc.text", value: .scripts) {
                ScriptsTab(path: $scriptsPath)
            }
            Tab("Studio", systemImage: "video.fill", value: .studio) {
                StudioTab(path: $studioPath)
            }
            Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                ProfileView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onReceive(NotificationCenter.default.publisher(for: .showStudio)) { _ in
            selectedTab.wrappedValue = .studio
        }
        .onChange(of: selectedTabRaw) { oldRaw, newRaw in
            guard AppTab(rawValue: oldRaw) == .studio,
                  isStudioRecording,
                  let newTab = AppTab(rawValue: newRaw),
                  newTab != .studio else { return }
            // Intercept — revert and confirm
            pendingTab = newTab
            selectedTabRaw = oldRaw
            showLeaveConfirm = true
        }
        .confirmationDialog("Leave Studio?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Stay in Studio", role: .cancel) {
                pendingTab = nil
            }
            Button("Leave & Keep Recording Paused", role: .destructive) {
                // Allow navigation; StudioView stays paused and can resume on return
                isStudioRecording = false
                if let pending = pendingTab {
                    selectedTabRaw = pending.rawValue
                }
                pendingTab = nil
            }
        } message: {
            Text("You're currently recording. Leave Studio and keep the take paused, or stay and continue.")
        }
    }
}

private struct ScriptsTab: View {
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            ScriptLibraryView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .studio(id): StudioDestination(scriptID: id)
                    case let .review(id): ReviewDestination(takeID: id)
                    }
                }
        }
    }
}

private struct StudioTab: View {
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            StudioView(initialScriptID: nil)
        }
    }
}

private struct StudioDestination: View {
    @Query private var scripts: [Script]
    let scriptID: Script.ID
    var body: some View {
        if let script = scripts.first(where: { $0.id == scriptID }) {
            // Pushed on a stack: keep the native back button and swipe-back.
            StudioView(initialScriptID: script.id, showsDismissButton: false)
        } else {
            ContentUnavailableView { Label("Script Not Found", systemImage: "exclamationmark.triangle") } description: {
                Text("The script was deleted.")
            }
        }
    }
}

private struct ReviewDestination: View {
    @Query private var takes: [Take]
    let takeID: Take.ID
    var body: some View {
        if let take = takes.first(where: { $0.id == takeID }) {
            ReviewView(take: take)
        } else {
            ContentUnavailableView { Label(
                "Take Not Found",
                systemImage: "film.slash"
            )
            } description: { Text("This recording could not be found.") }
        }
    }
}

#Preview {
    RootTabView().modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true)
}
