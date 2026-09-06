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
    @Environment(ProEntitlementService.self)
    private var pro
    @State private var path = NavigationPath()
    @State private var showPaywall = false

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
                Section("Subscription") {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Label("OneTake Pro", systemImage: "crown.fill")
                            Spacer()
                            Text(pro.isPro ? "Active" : "Free")
                                .foregroundStyle(pro.isPro ? Color.appAccent : .secondary)
                                .font(.subheadline)
                        }
                    }
                    .accessibilityLabel(pro.isPro ? "OneTake Pro, active" : "OneTake Pro, free plan")
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
                    NavigationLink {
                        TermsView(mode: .readOnly)
                    } label: {
                        Label("Terms & Privacy", systemImage: "doc.text.fill")
                    }
                    .accessibilityLabel("Terms and Privacy Policy")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .sheet(isPresented: $showPaywall) {
                NavigationStack {
                    PaywallView(showsClose: true)
                }
            }
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
    return ProfileView().modelContainer(c).environment(ProEntitlementService.previewLocked)
}

#Preview("Empty") {
    ProfileView().modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true)
        .environment(ProEntitlementService.previewUnlocked)
}

// swiftlint:enable force_try force_cast force_unwrapping
