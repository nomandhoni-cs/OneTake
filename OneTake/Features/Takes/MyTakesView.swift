//
//  MyTakesView.swift
//  OneTake
//

//  See: docs/ARCHITECTURE.md §6 (My Takes) + openspec/changes/unified-tabs-lut-preview-blade-trim/specs/blade-timeline-editing/spec.md
import SwiftData
import SwiftUI

//
//  MyTakesView.swift
//  OneTake
//
//  Aggregated Takes library — reverse-chronological, day-grouped, searchable.
//  Shows resolved script title, duration, LUT/trim badges, and file-missing state.
//  Uses `ContentUnavailableView` for empty/search-empty, per HIG.
//  Best practices: `@Query` live fetch, pure `var body`, extracted `MyTakesRow` struct,
//  no type-erased wrapper, `guard let` for optional unwrapping, `[weak self]` where needed.
//
import AVFoundation

/// Guideline-driven helpers for the Takes library — pure, UI-free, unit-tested.
/// Predicates are enablement heuristics; mutating actions re-validate (§11.1).
enum TakesLibrary {
    /// Editable window: explicit trim, else full duration (10s fallback mirrors legacy takes).
    static func trimWindow(of take: Take) -> (start: Double, end: Double) {
        let duration = take.duration > 0 ? take.duration : 10
        let start = take.trimStartSeconds ?? 0
        return (start, start + (take.trimDurationSeconds ?? duration))
    }

    static func effectiveTrimLength(of take: Take) -> TimeInterval {
        let window = trimWindow(of: take)
        return max(window.end - window.start, 0)
    }

    static func canBladeSplit(_ take: Take) -> Bool {
        effectiveTrimLength(of: take) >= 1.1
    }

    static func canDeleteLastSegment(of take: Take) -> Bool {
        take.bladeSegments().count > 1
    }

    static func matchesScope(_ take: Take, scope: TakeScope) -> Bool {
        scope == .all || take.isReaction
    }

    /// Localized day key ("Today"/"Yesterday" in-device locale, else medium date).
    /// Local formatter per call: thread-safe by construction for parallel tests;
    /// the view's render loop uses its own cached `dayFormatter`.
    static func relativeDayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    static func freestyleTitle() -> String {
        String(localized: "Freestyle / No script")
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Single VoiceOver label for a row (spec `takes-row-a11y`).
    static func rowAccessibilityLabel(title: String, take: Take, fileExists: Bool) -> String {
        var parts = [title, formatDuration(take.duration)]
        if take.trimRange != nil {
            parts.append(String(localized: "Trimmed"))
        }
        if take.lutPreset != LUTPreset.natural.rawValue {
            parts.append(LUTPreset(rawValue: take.lutPreset)?.displayName ?? take.lutPreset)
        }
        if take.isReaction {
            parts.append(String(localized: "Reaction"))
        }
        parts.append(relativeDayKey(for: take.createdAt))
        if !fileExists {
            parts.append(String(localized: "File missing"))
        }
        return parts.joined(separator: ", ")
    }
}

/// Visible library filter — the native, discoverable replacement for the old
/// hidden "reaction" search keyword (§1.6, §10.1).
enum TakeScope: String, CaseIterable, Hashable {
    case all
    case reactions
}

// swiftlint:disable force_try force_cast force_unwrapping

struct MyTakesView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \Take.createdAt, order: .reverse)
    private var takes: [Take]
    @Query(sort: \Script.updatedAt, order: .reverse)
    private var scripts: [Script]

    @State private var searchText = ""
    @State private var takeScope: TakeScope = .all
    @State private var navigationPath = NavigationPath()
    @State private var showStudio = false
    @State private var deleteTarget: Take?
    @State private var showDeleteConfirm = false
    @State private var pendingSegmentDelete: Take?
    @State private var fileMissingAlert = false
    /// Disk presence by take — refreshed off-body in `.task(id:)` (§14.2).
    /// `nil` = unchecked; rows assume present until the check lands.
    @State private var existingFiles: Set<Take.ID>?
    @State private var haptics = HapticsService()

    /// Cached for the render loop — one formatter for all rows per evaluation.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private func fileExists(_ take: Take) -> Bool {
        existingFiles.map { $0.contains(take.id) } ?? true
    }

    private var scriptTitleByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: scripts.map { ($0.id, $0.title) })
    }

    private func resolvedTitle(for take: Take) -> String {
        if let title = scriptTitleByID[take.scriptID], !title.isEmpty {
            return title
        }
        return TakesLibrary.freestyleTitle()
    }

    private var filteredTakes: [Take] {
        let scoped = takes.filter { TakesLibrary.matchesScope($0, scope: takeScope) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scoped }
        return scoped.filter { resolvedTitle(for: $0).localizedCaseInsensitiveContains(query) }
    }

    private var grouped: [(key: String, takes: [Take])] {
        let dict: [String: [Take]] = Dictionary(grouping: filteredTakes) {
            Self.dayFormatter.string(from: $0.createdAt)
        }
        var order: [String: Date] = [:]
        for (k, v) in dict {
            order[k] = v.map(\.createdAt).max() ?? .distantPast
        }
        let sortedKeys = dict.keys.sorted { (order[$0] ?? .distantPast) > (order[$1] ?? .distantPast) }
        return sortedKeys.map { key in
            let vals = dict[key] ?? []
            let sortedVals = vals.sorted { $0.createdAt > $1.createdAt }
            return (key, sortedVals)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if takes.isEmpty, searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No takes yet", systemImage: "film.stack")
                    } description: {
                        Text("Record your first take to see it here.")
                    } actions: {
                        Button("Record your first take") { showStudio = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filteredTakes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(grouped, id: \.key) { group in
                            Section(header: Text(group.key)) {
                                ForEach(group.takes) { take in
                                    let exists = fileExists(take)
                                    Button { openTake(take) } label: {
                                        MyTakesRow(
                                            take: take,
                                            scriptTitle: resolvedTitle(for: take),
                                            fileExists: exists
                                        )
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(TakesLibrary.rowAccessibilityLabel(
                                        title: resolvedTitle(for: take),
                                        take: take,
                                        fileExists: exists
                                    ))
                                    .accessibilityHint(exists ? "Opens review" : "Shows options for the missing file")
                                    .accessibilityAddTraits(.isButton)
                                    .contextMenu {
                                        Section("Adjust") {
                                            Button {
                                                navigationPath.append(Route.review(take.id))
                                            } label: { Label("Trim", systemImage: "scissors") }
                                            Button {
                                                bladeSplitTake(take)
                                            } label: {
                                                Label("Blade Split at Middle", systemImage: "scissors.badge.ellipsis")
                                            }
                                            .disabled(!TakesLibrary.canBladeSplit(take))
                                        }
                                        Section("Color") {
                                            Menu {
                                                ForEach(LUTPreset.allCases) { preset in
                                                    Button {
                                                        take.lutPreset = preset.rawValue
                                                        try? modelContext.save()
                                                        haptics.impact(style: .light)
                                                    } label: {
                                                        HStack(spacing: 8) {
                                                            LUTSwatchView(preset: preset)
                                                            Text(preset.displayName)
                                                            if take.lutPreset == preset.rawValue {
                                                                Image(systemName: "checkmark")
                                                            }
                                                        }
                                                    }
                                                }
                                            } label: { Label("LUT", systemImage: "paintpalette") }
                                        }
                                        Section("Output") {
                                            if exists {
                                                ShareLink(item: take.fileURL) {
                                                    Label("Share", systemImage: "square.and.arrow.up")
                                                }
                                            }
                                        }
                                        Section("Destructive") {
                                            Button(role: .destructive) {
                                                pendingSegmentDelete = take
                                            } label: {
                                                Label("Delete Last Segment", systemImage: "trash")
                                            }
                                            .disabled(!TakesLibrary.canDeleteLastSegment(of: take))
                                            Button(role: .destructive) {
                                                deleteTarget = take
                                                showDeleteConfirm = true
                                            } label: { Label("Delete Take", systemImage: "trash") }
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            deleteTarget = take
                                            showDeleteConfirm = true
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            navigationPath.append(Route.review(take.id))
                                        } label: { Label("Edit", systemImage: "pencil") }
                                            .tint(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("My Takes")
            // Keep search at the top (navigation bar drawer), not bottomBar.
            // On iOS 26, `searchable` without placement can collapse to bottomBar inside TabView.
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search script title")
            .searchScopes($takeScope) {
                Text("All").tag(TakeScope.all)
                Text("Reactions").tag(TakeScope.reactions)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showStudio = true } label: { Label("Record", systemImage: "video.fill.badge.plus") }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .review(id):
                    MyTakesReviewDestination(takeID: id)
                case let .studio(id):
                    MyTakesStudioDestination(scriptID: id)
                }
            }
            .alert("File missing", isPresented: $fileMissingAlert) {
                Button("OK", role: .cancel) {}
                Button("Delete Take", role: .destructive) {
                    if let t = deleteTarget {
                        performDelete(t)
                    }
                }
            } message: {
                Text("The video file for this take is missing on disk.")
            }
            .confirmationDialog("Delete Take?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget {
                        performDelete(target)
                    }
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This will delete the take and its video file. This cannot be undone.")
            }
            .confirmationDialog(
                "Delete Last Segment?",
                isPresented: Binding(get: { pendingSegmentDelete != nil }, set: {
                    if !$0 {
                        pendingSegmentDelete = nil
                    }
                }),
                titleVisibility: .visible
            ) {
                Button("Delete Segment", role: .destructive) {
                    if let target = pendingSegmentDelete {
                        deleteLastBladeSegment(of: target)
                        haptics.impact(style: .medium)
                    }
                    pendingSegmentDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingSegmentDelete = nil }
            } message: {
                Text("This permanently removes the last segment of this take. This cannot be undone.")
            }
            .task(id: takes.map(\.id)) {
                // Disk presence off the render path: stat syscalls must never run in `body`.
                let entries = takes.map { ($0.id, $0.fileURL) }
                let found = await Task.detached(priority: .utility) {
                    var known = Set<Take.ID>()
                    let manager = FileManager.default
                    for (id, url) in entries where manager.fileExists(atPath: url.path) {
                        known.insert(id)
                    }
                    return known
                }.value
                existingFiles = found
            }
        }
        .fullScreenCover(isPresented: $showStudio) {
            // Freestyle launch from My Takes: no script preselected (nil)
            StudioView(initialScriptID: nil)
        }
    }

    private func openTake(_ take: Take) {
        // Live check (not the cache): the file may vanish while the list is open.
        if FileManager.default.fileExists(atPath: take.fileURL.path) {
            navigationPath.append(Route.review(take.id))
        } else {
            deleteTarget = take
            fileMissingAlert = true
        }
    }

    private func performDelete(_ take: Take) {
        let segDir = ExportService.takesDirectory()
            .appendingPathComponent("segments")
            .appendingPathComponent(take.id.uuidString)
        try? FileManager.default.removeItem(at: segDir)
        try? FileManager.default.removeItem(at: take.fileURL)
        modelContext.delete(take)
        deleteTarget = nil
    }

    private func bladeSplitTake(_ take: Take) {
        let window = TakesLibrary.trimWindow(of: take)
        let mid = (window.start + window.end) / 2
        guard mid > window.start + 0.1, mid < window.end - 0.1 else { return }
        take.clipSegments(start: window.start, end: window.end)
        guard take.split(at: mid) != nil else { return }
        try? modelContext.save()
        haptics.impact(style: .medium)
    }

    private func deleteLastBladeSegment(of take: Take) {
        let window = TakesLibrary.trimWindow(of: take)
        take.clipSegments(start: window.start, end: window.end)
        let count = take.bladeSegments().count
        guard count > 1, take.deleteSegment(at: count - 1) else { return }
        try? modelContext.save()
    }
}

private struct MyTakesReviewDestination: View {
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

private struct MyTakesStudioDestination: View {
    @Query private var scripts: [Script]
    let scriptID: Script.ID
    var body: some View {
        if let script = scripts.first(where: { $0.id == scriptID }) {
            StudioView(initialScriptID: script.id)
        } else {
            ContentUnavailableView { Label(
                "Script Not Found",
                systemImage: "exclamationmark.triangle"
            )
            } description: { Text("The script was deleted.") }
        }
    }
}

private struct MyTakesRow: View {
    let take: Take
    let scriptTitle: String
    let fileExists: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.85))
                Image(systemName: "film")
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(scriptTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Label(TakesLibrary.formatDuration(take.duration), systemImage: "clock")
                        .font(.caption2).foregroundStyle(.secondary)
                    if take.trimRange != nil {
                        Text("Trimmed").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(
                            Color.blue.opacity(0.18),
                            in: Capsule()
                        )
                    }
                    if take.lutPreset != LUTPreset.natural.rawValue {
                        Text(LUTPreset(rawValue: take.lutPreset)?.displayName ?? take.lutPreset)
                            .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(
                                Color.orange.opacity(0.18),
                                in: Capsule()
                            )
                    }
                    if take.isReaction {
                        Text("Reaction").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(
                            Color.purple.opacity(0.18),
                            in: Capsule()
                        )
                    }
                }
                Text(take.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if !fileExists {
                Text("File missing").font(.caption2.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(
                        Color.red,
                        in: Capsule()
                    )
            } else {
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview("Empty") {
    MyTakesView().modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true)
}

#Preview("Populated") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Script.self, Take.self, ScriptCategory.self, configurations: config)
    let ctx = ModelContext(container)
    let s = Script(title: "Demo Script", body: "Hello")
    ctx.insert(s)
    let t1 = Take(scriptID: s.id, fileURL: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 32, script: s)
    let t2 = Take(
        scriptID: s.id,
        fileURL: URL(fileURLWithPath: "/tmp/b.mp4"),
        duration: 75,
        lutPreset: LUTPreset.warmStudio.rawValue,
        script: s
    )
    ctx.insert(t1); ctx.insert(t2)
    return MyTakesView().modelContainer(container)
}

#Preview("Missing file") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Script.self, Take.self, ScriptCategory.self, configurations: config)
    let ctx = ModelContext(container)
    let s = Script(title: "Demo", body: "")
    ctx.insert(s)
    let t = Take(scriptID: s.id, fileURL: URL(fileURLWithPath: "/nope/missing.mp4"), duration: 10, script: s)
    ctx.insert(t)
    return MyTakesView().modelContainer(container)
}

// swiftlint:enable force_try force_cast force_unwrapping
