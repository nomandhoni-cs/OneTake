//
//  ProfileView.swift
//  OneTake
//

import SwiftData
import SwiftUI

///
///  ProfileView.swift
///  OneTake
///
///  Profile tab — grouped inset list with preferences, summary, about.
///  Independent `NavigationStack` per tab to retain depth.
///  Best practices: `@Query` for live count, extracted detail structs, no force unwrap.
///
struct ProfileView: View {
    @Query(sort: \Take.createdAt, order: .reverse)
    private var takes: [Take]
    @State private var path = NavigationPath()

    private var takesSummary: String {
        let count = takes.count
        let total = takes.reduce(0) { $0 + $1.duration }
        let s = Int(total.rounded())
        return String(format: "%d takes · %d:%02d", count, s / 60, s % 60)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Preferences") {
                    NavigationLink("Camera defaults") { CameraDefaultsDetail() }
                    NavigationLink("Countdown") { CountdownDetail() }
                    NavigationLink("Aspect / LUT") { AspectLUTDetail() }
                }
                Section("Takes") {
                    HStack {
                        Label("Summary", systemImage: "film.stack")
                        Spacer()
                        Text(takesSummary).foregroundStyle(.secondary).font(.subheadline)
                    }
                }
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundStyle(.secondary)
                    }
                    // swiftlint:disable:next force_unwrapping
                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        Label("Privacy Settings", systemImage: "hand.raised")
                    }
                }
                Section("Account") {
                    Text("Sign in — coming soon").foregroundStyle(.secondary)
                }
                Section("Documentation") {
                    // Repeatedly visible on Profile — quick links for new contributors.
                    // See AGENTS.md §2 (Documentation Map) for the full hub.
                    VStack(alignment: .leading, spacing: 2) {
                        Label("AGENTS.md — Start here", systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Doc map, where data comes from, where code lives, how to work, lint contract.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label("ARCHITECTURE.md — Deep dive", systemImage: "building.columns.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Layers, app lifecycle, 4-tab navigation, persistence (Script/Take/bladeCuts), Core services, theme.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label("CODEMAP.md — File-by-file", systemImage: "map.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Every folder/file and what it owns — use to find where a responsibility lives.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label("GETTING_STARTED.md — Build & test", systemImage: "hammer.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Prerequisites, open *.xcodeproj, xcodebuild, swiftlint/swiftformat, simulator tips.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label("LINT_REPORT.md — Best practices", systemImage: "checkmark.shield.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Current 0 violations, triage, config (.swiftlint.yml 700/900).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label("openspec/ — Spec-driven", systemImage: "doc.text.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Specs + changes (unified-tabs-lut-preview-blade-trim 17/17).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
        }
    }
}

private struct CameraDefaultsDetail: View {
    @AppStorage("resolution")
    var resolution = StudioSettings.defaultResolution.rawValue
    @AppStorage("frameRate")
    var frameRate = StudioSettings.defaultFrameRate.rawValue
    @AppStorage("mirrorMode")
    var mirror = StudioSettings.defaultMirror
    var body: some View {
        Form {
            Picker("Resolution", selection: $resolution) {
                ForEach(Resolution.allCases) { r in Text(r.displayName).tag(r.rawValue) }
            }
            Picker("Frame Rate", selection: $frameRate) {
                ForEach(FrameRate.allCases) { f in Text(f.displayName).tag(f.id) }
            }
            Toggle("Mirror", isOn: $mirror)
        }.navigationTitle("Camera defaults").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CountdownDetail: View {
    @AppStorage("countdownEnabled")
    var enabled = true
    var body: some View {
        Form { Toggle("Countdown before record", isOn: $enabled) }
            .navigationTitle("Countdown").navigationBarTitleDisplayMode(.inline)
    }
}

private struct AspectLUTDetail: View {
    @AppStorage("aspectRatio")
    var aspect = StudioSettings.defaultAspect.rawValue
    var body: some View {
        Form {
            Picker("Aspect", selection: $aspect) {
                ForEach(AspectRatio.allCases) { a in Text(a.displayName).tag(a.rawValue) }
            }
        }.navigationTitle("Aspect / LUT").navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Populated") {
    // swiftlint:disable:next force_try
    let c = try! ModelContainer(
        for: Script.self,
        Take.self,
        ScriptCategory.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = ModelContext(c)
    ctx.insert(Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 32))
    ctx.insert(Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/b.mp4"), duration: 60))
    return ProfileView().modelContainer(c)
}

#Preview("Empty") {
    ProfileView().modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true)
}

// swiftlint:enable force_try force_cast force_unwrapping
