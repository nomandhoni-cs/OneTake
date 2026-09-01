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

// swiftlint:disable force_try force_cast force_unwrapping

struct MyTakesView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \Take.createdAt, order: .reverse)
    private var takes: [Take]
    @Query(sort: \Script.updatedAt, order: .reverse)
    private var scripts: [Script]

    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()
    @State private var showStudio = false
    @State private var deleteTarget: Take?
    @State private var showDeleteConfirm = false
    @State private var fileMissingAlert = false

    private var scriptTitleByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: scripts.map { ($0.id, $0.title) })
    }

    private func resolvedTitle(for take: Take) -> String {
        if let t = scriptTitleByID[take.scriptID], !t.isEmpty {
            return t
        }
        return "Freestyle / No script"
    }

    private var filteredTakes: [Take] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return takes }
        return takes.filter { resolvedTitle(for: $0).localizedCaseInsensitiveContains(q) }
    }

    private var grouped: [(key: String, takes: [Take])] {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        let cal = Calendar.current
        func dayKey(for date: Date) -> String {
            if cal.isDateInToday(date) {
                return "Today"
            }
            if cal.isDateInYesterday(date) {
                return "Yesterday"
            }
            return fmt.string(from: date)
        }
        let dict: [String: [Take]] = Dictionary(grouping: filteredTakes) { dayKey(for: $0.createdAt) }
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
                                    Button { openTake(take) } label: {
                                        MyTakesRow(
                                            take: take,
                                            scriptTitle: resolvedTitle(for: take),
                                            fileExists: FileManager.default.fileExists(atPath: take.fileURL.path)
                                        )
                                    }
                                    .contextMenu {
                                        Section("Adjust") {
                                            Button {
                                                navigationPath.append(Route.review(take.id))
                                            } label: { Label("Trim", systemImage: "scissors") }
                                            Button {
                                                bladeSplitTake(take)
                                            } label: {
                                                Label("Blade Split at Playhead", systemImage: "scissors.badge.ellipsis")
                                            }
                                            .disabled((take.duration) < 1.1)
                                            Button(role: .destructive) {
                                                deleteLastBladeSegment(of: take)
                                            } label: {
                                                Label("Delete Last Segment", systemImage: "trash")
                                            }
                                            .disabled(take.bladeCuts?.isEmpty ?? true)
                                        }
                                        Section("Color") {
                                            Menu {
                                                ForEach(LUTPreset.allCases) { preset in
                                                    Button {
                                                        take.lutPreset = preset.rawValue
                                                        try? modelContext.save()
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
                                            if FileManager.default.fileExists(atPath: take.fileURL.path) {
                                                ShareLink(item: take.fileURL) {
                                                    Label("Share", systemImage: "square.and.arrow.up")
                                                }
                                            }
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
                    if let t = deleteTarget {
                        performDelete(t)
                    }
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This will delete the take and its video file. This cannot be undone.")
            }
        }
        .fullScreenCover(isPresented: $showStudio) {
            // Freestyle launch from My Takes: no script preselected (nil)
            StudioView(initialScriptID: nil)
        }
    }

    private func openTake(_ take: Take) {
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
        let duration = take.duration > 0 ? take.duration : 10
        let trimStart = take.trimStartSeconds ?? 0
        let trimEnd = (take.trimStartSeconds ?? 0) + (take.trimDurationSeconds ?? duration)
        let mid = (trimStart + trimEnd) / 2
        guard mid > trimStart + 0.1, mid < trimEnd - 0.1 else { return }
        if let cuts = take.bladeCuts, cuts.contains(where: { abs($0 - mid) < 0.1 }) {
            return
        }
        var cuts = take.bladeCuts ?? []
        cuts.append(mid)
        cuts.sort()
        var deduped: [Double] = []
        for value in cuts {
            if let last = deduped.last, abs(last - value) < 0.1 {
                continue
            }
            deduped.append(value)
        }
        take.bladeCuts = deduped
        try? modelContext.save()
    }

    private func deleteLastBladeSegment(of take: Take) {
        guard var cuts = take.bladeCuts, !cuts.isEmpty else { return }
        cuts.removeLast()
        take.bladeCuts = cuts.isEmpty ? nil : cuts
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
                    Label(formatDuration(take.duration), systemImage: "clock")
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

    private func formatDuration(_ d: TimeInterval) -> String {
        let s = Int(d.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
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
