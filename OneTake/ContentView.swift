//
//  ContentView.swift
//  OneTake
//

import SwiftData
import SwiftUI

// swiftlint:disable:next orphaned_doc_comment
///
///  ContentView.swift
///  OneTake
///
///  Root content — switches between tab shell (`RootTabView`) and legacy stack
///  via `ENABLE_TAB_SHELL` flag for snapshot tests. Defines shared `Route` enum.
///  Uses `SceneStorage`/`AppStorage` for tab persistence, no force unwraps.
///
// swiftlint:disable:next identifier_name
let ENABLE_TAB_SHELL = true // swiftlint:disable:next identifier_name

extension Notification.Name {
    static let showStudio = Notification.Name("showStudio")
}

enum Route: Hashable {
    case studio(Script.ID)
    case review(Take.ID)
}

struct ContentView: View {
    var body: some View {
        if ENABLE_TAB_SHELL {
            RootTabView()
        } else {
            LegacyContentView()
        }
    }
}

private struct LegacyContentView: View {
    @State private var navigationPath = NavigationPath()
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScriptLibraryView(path: $navigationPath)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .studio(id): StudioDestination(scriptID: id)
                    case let .review(id): ReviewDestination(takeID: id)
                    }
                }
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
                Text("The script you tried to open no longer exists. It may have been deleted.")
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

struct ScriptLibraryView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \Script.updatedAt, order: .reverse)
    private var scripts: [Script]
    @Query(sort: \ScriptCategory.createdAt)
    private var categories: [ScriptCategory]
    @Binding var path: NavigationPath
    var showStudio: Binding<Bool>?

    @State private var searchText = ""
    @State private var editingScript: Script?
    @State private var isNewScript = false
    @State private var filterCategoryID: ScriptCategory.ID?
    @State private var showManageCategories = false
    @AppStorage("scriptSort")
    private var scriptSort = ScriptSortMode.updated.rawValue

    private var sortMode: ScriptSortMode {
        ScriptSortMode(rawValue: scriptSort) ?? .updated
    }

    private var filterCategory: ScriptCategory? {
        guard let id = filterCategoryID else { return nil }
        return categories.first(where: { $0.id == id })
    }

    private var searchTextTrimmed: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchMatches: [Script] {
        let query = searchTextTrimmed
        guard !query.isEmpty else { return scripts }
        return scripts.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    private var visibleScripts: [Script] {
        let base = searchMatches
        guard let category = filterCategory else { return base }
        return base.filter { $0.category?.id == category.id }
    }

    private var sortedScripts: [Script] {
        visibleScripts.sorted { lhs, rhs in
            switch sortMode {
            case .updated: lhs.updatedAt > rhs.updatedAt
            case .created: lhs.createdAt > rhs.createdAt
            case .title: lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
        }
    }

    /// Scripts with a category, keyed for section grouping.
    private var scriptsByCategoryID: [UUID: [Script]] {
        var dict: [UUID: [Script]] = [:]
        for script in sortedScripts {
            guard let category = script.category else { continue }
            dict[category.id, default: []].append(script)
        }
        return dict
    }

    private var uncategorizedScripts: [Script] {
        sortedScripts.filter { $0.category == nil }
    }

    var body: some View {
        Group {
            if scripts.isEmpty, searchText.isEmpty {
                ContentUnavailableView {
                    Label("No Scripts Yet", systemImage: "doc.text")
                } description: {
                    Text("Write your first script and record it in one take.")
                } actions: {
                    Button("Create First Script") { openNewScriptEditor() }
                        .buttonStyle(.borderedProminent)
                }
            } else if visibleScripts.isEmpty {
                if !searchTextTrimmed.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView {
                        Label("No Scripts in This Category", systemImage: "tray")
                    } description: {
                        Text("Move a script here or switch back to All.")
                    }
                }
            } else {
                List {
                    if !categories.isEmpty, filterCategory == nil, searchTextTrimmed.isEmpty {
                        categorySections
                    } else {
                        Section {
                            ForEach(sortedScripts) { script in
                                CategoryScriptRow(
                                    script: script,
                                    categories: categories,
                                    onOpen: { openEditor(for: script) },
                                    onDuplicate: { duplicate(script) },
                                    onDelete: { delete(script) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("OneTake")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search scripts")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                sortMenu
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    openNewScriptEditor()
                } label: {
                    Label("Add Script", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !categories.isEmpty {
                CategoryFilterBar(
                    categories: categories,
                    scripts: scripts,
                    selectedID: $filterCategoryID,
                    showManage: { showManageCategories = true }
                )
            } else if !scripts.isEmpty {
                // Zero categories: single discoverable entry instead of a
                // chip bar with nothing to filter.
                Button {
                    showManageCategories = true
                } label: {
                    Label("Add Category", systemImage: "tag")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesSheet()
        }
        .sheet(isPresented: Binding(
            get: { editingScript != nil },
            set: {
                if !$0 {
                    editingScript = nil; isNewScript = false
                }
            }
        )) {
            if let script = editingScript {
                ScriptEditorSheet(script: script, path: $path)
            }
        }
    }

    // MARK: - Actions

    private func openNewScriptEditor() {
        let script = Script(title: "", body: "")
        // New scripts inherit the active filter's category.
        if let category = filterCategory {
            script.category = category
        }
        modelContext.insert(script)
        editingScript = script
        isNewScript = true
    }

    private func openEditor(for script: Script) {
        editingScript = script
        isNewScript = false
    }

    private func duplicate(_ script: Script) {
        let copy = Script(
            title: script.title.isEmpty ? "Untitled copy" : script.title + " copy",
            body: script.body,
            category: script.category
        )
        modelContext.insert(copy)
    }

    private func delete(_ script: Script) {
        // Cascade rule removes Take records; delete their files from disk first.
        for take in script.takes {
            try? FileManager.default.removeItem(at: take.fileURL)
        }
        modelContext.delete(script)
    }

    // MARK: - Section builders

    @ViewBuilder
    // swiftlint:disable:next attributes
    private var categorySections: some View {
        ForEach(categories) { category in
            if let group = scriptsByCategoryID[category.id], !group.isEmpty {
                Section {
                    ForEach(group) { script in
                        CategoryScriptRow(
                            script: script,
                            categories: categories,
                            onOpen: { openEditor(for: script) },
                            onDuplicate: { duplicate(script) },
                            onDelete: { delete(script) }
                        )
                    }
                } header: {
                    CategorySectionHeader(category: category)
                }
            }
        }
        if !uncategorizedScripts.isEmpty {
            Section("Uncategorized") {
                ForEach(uncategorizedScripts) { script in
                    CategoryScriptRow(
                        script: script,
                        categories: categories,
                        onOpen: { openEditor(for: script) },
                        onDuplicate: { duplicate(script) },
                        onDelete: { delete(script) }
                    )
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $scriptSort) {
                ForEach(ScriptSortMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }
}

/// Library sort orders, persisted via `@AppStorage`.
enum ScriptSortMode: String, CaseIterable, Identifiable {
    case updated
    case created
    case title

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .updated: "Last Updated"
        case .created: "Date Created"
        case .title: "Title"
        }
    }
}

// MARK: - Filter bar

/// Horizontally scrolling category filter chips + manage entry, pinned above
/// the list so it stays visible while scrolling.
struct CategoryFilterBar: View {
    let categories: [ScriptCategory]
    let scripts: [Script]
    @Binding var selectedID: ScriptCategory.ID?
    var showManage: () -> Void

    private var countByCategoryID: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for script in scripts {
            guard let id = script.category?.id else { continue }
            counts[id, default: 0] += 1
        }
        return counts
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    category: allChip,
                    count: scripts.count,
                    isSelected: selectedID == nil,
                    action: { selectedID = nil }
                )
                ForEach(categories) { category in
                    CategoryChip(
                        category: category,
                        count: countByCategoryID[category.id] ?? 0,
                        isSelected: selectedID == category.id,
                        action: { selectedID = category.id }
                    )
                }
                Button(action: showManage) {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .accessibilityLabel("Manage categories")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    /// Synthetic "All" chip that reuses the pill design without a model.
    private var allChip: ScriptCategory {
        ScriptCategory(name: "All", symbolName: "tray.full")
    }
}

// MARK: - Section header

/// Category section header: icon dot, name, script count.
struct CategorySectionHeader: View {
    let category: ScriptCategory

    var body: some View {
        HStack(spacing: 6) {
            CategoryIconView(symbolName: category.symbolName)
            Text(category.name)
            Text("· \(category.scripts.count)")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }
}

struct ScriptRow: View {
    let script: Script

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(script.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(script.body.isEmpty ? "No content yet" : script.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(script.updatedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if let category = script.category {
                CategoryBadge(category: category)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview("Populated") {
    ContentView()
        .modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true)
}

#Preview("Empty") {
    ContentView()
        .modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true)
}
