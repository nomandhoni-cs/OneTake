//
//  ScriptCategoryViews.swift
//  OneTake
//
//  UI kit for script categories: style tokens, chips, badges, menus,
//  the editor's category picker, and the manage-categories sheet.
//

import SwiftData
import SwiftUI

// MARK: - Category style

/// Circular palette that pairs an SF Symbol with a fixed background color so
/// categories stay visually distinct in chips, badges, and menus alike.
enum CategoryStyle: String, CaseIterable, Identifiable {
    case tag, folder, briefcase, sparkles, flame, star, globe, graduationCap, bubble, wand

    var id: String {
        rawValue
    }

    /// The SF Symbol rendered inside the dot.
    var symbolName: String {
        switch self {
        case .tag: "tag"
        case .folder: "folder"
        case .briefcase: "briefcase"
        case .sparkles: "sparkles"
        case .flame: "flame"
        case .star: "star"
        case .globe: "globe"
        case .graduationCap: "graduationcap"
        case .bubble: "bubble.left"
        case .wand: "wand.and.stars"
        }
    }

    /// Stable per-style hue. Values chosen for legibility on grouped-list
    /// backgrounds in both light and dark mode.
    private var tint: Color {
        switch self {
        case .tag: Color(red: 0.55, green: 0.28, blue: 0.96) // purple
        case .folder: Color(red: 0.20, green: 0.48, blue: 0.96) // blue
        case .briefcase: Color(red: 0.16, green: 0.50, blue: 0.24) // green
        case .sparkles: Color(red: 0.72, green: 0.52, blue: 1.00) // pink-lilac
        case .flame: Color(red: 0.93, green: 0.35, blue: 0.16) // orange
        case .star: Color(red: 0.95, green: 0.71, blue: 0.05) // yellow
        case .globe: Color(red: 0.12, green: 0.62, blue: 0.70) // teal
        case .graduationCap: Color(red: 0.75, green: 0.24, blue: 0.24) // red
        case .bubble: Color(red: 0.38, green: 0.56, blue: 0.96) // periwinkle
        case .wand: Color(red: 0.45, green: 0.35, blue: 0.90) // violet
        }
    }

    /// Colored dot + white symbol used in chips and list rows.
    var icon: some View {
        ZStack {
            Circle().fill(tint)
            Image(systemName: symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Icon fallback

/// Icon dot that degrades gracefully when `symbolName` isn't a known style
/// (e.g. the synthetic "All" chip, or data written by a future version).
struct CategoryIconView: View {
    let symbolName: String

    var body: some View {
        if let style = CategoryStyle(rawValue: symbolName) {
            style.icon
        } else {
            ZStack {
                Circle().fill(Color.primary.opacity(0.12))
                Image(systemName: symbolName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 16, height: 16)
        }
    }
}

// MARK: - Category chip (library filter)

/// Pill-shaped category filter button for the library's filter bar.
struct CategoryChip: View {
    let category: ScriptCategory
    let count: Int
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                CategoryIconView(symbolName: category.symbolName)
                Text(category.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule().fill(Color.appAccent.opacity(0.16))
                }
            }
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? Color.appAccent : Color.primary.opacity(0.12),
                    lineWidth: 1
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by \(category.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Category badge (script row)

/// Small inline badge showing a script's category.
struct CategoryBadge: View {
    let category: ScriptCategory

    var body: some View {
        HStack(spacing: 4) {
            CategoryIconView(symbolName: category.symbolName)
            Text(category.name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

// MARK: - Category move menu

/// Context-menu submenu for reassigning a script's category.
struct CategoryMoveMenu: View {
    let script: Script
    let categories: [ScriptCategory]
    var onAssign: (ScriptCategory?) -> Void

    var body: some View {
        Menu {
            Button {
                onAssign(nil)
            } label: {
                Label("None", systemImage: script.category == nil ? "checkmark" : "tag")
            }
            ForEach(categories) { category in
                Button {
                    onAssign(category)
                } label: {
                    Label(category.name, systemImage: script.category?.id == category.id ? "checkmark" : category.symbolName)
                }
            }
        } label: {
            Label("Move to Category", systemImage: "tag")
        }
    }
}

// MARK: - Library row

/// Script library row with category badge, swipe actions, and a context menu
/// carrying the move-to-category submenu.
struct CategoryScriptRow: View {
    let script: Script
    let categories: [ScriptCategory]
    var onOpen: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @Environment(\.modelContext)

    // swiftlint:disable:next attributes
    private var modelContext

    var body: some View {
        Button(action: onOpen) {
            ScriptRow(script: script)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(.indigo)
        }
        .contextMenu {
            CategoryMoveMenu(
                script: script,
                categories: categories,
                onAssign: { category in
                    script.category = category
                    try? modelContext.save()
                }
            )
            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Editor category picker

/// Bottom bar for the editor sheet: current category chip + "change" menu.
struct CategoryPickerBar: View {
    @Bindable var script: Script
    @Query(sort: \ScriptCategory.createdAt)
    private var categories: [ScriptCategory]

    @Environment(\.modelContext)

    // swiftlint:disable:next attributes
    private var modelContext
    @State private var showNewCategoryAlert = false
    @State private var newCategoryName = ""

    var body: some View {
        HStack(spacing: 8) {
            if let category = script.category {
                CategoryBadge(category: category)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("No category")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }

            Menu {
                categoryMenuContent
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .accessibilityLabel("Choose category")
        }
        .alert("New Category", isPresented: $showNewCategoryAlert) {
            TextField("Name", text: $newCategoryName)
            Button("Create") {
                createCategoryAndAssign()
            }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        } message: {
            Text("Categories group related scripts.")
        }
    }

    @ViewBuilder private var categoryMenuContent: some View {
        Button {
            script.category = nil
        } label: {
            if script.category == nil {
                Label("No category", systemImage: "checkmark")
            } else {
                Label("No category", systemImage: "tag")
            }
        }
        ForEach(categories) { category in
            Button {
                script.category = category
                script.updatedAt = Date()
            } label: {
                if script.category?.id == category.id {
                    Label(category.name, systemImage: "checkmark")
                } else {
                    Label(category.name, systemImage: category.symbolName)
                }
            }
        }
        Divider()
        Button {
            showNewCategoryAlert = true
        } label: {
            Label("New Category…", systemImage: "plus")
        }
    }

    private func createCategoryAndAssign() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let category = ScriptCategory(name: trimmed)
        modelContext.insert(category)
        script.category = category
        script.updatedAt = Date()
        try? modelContext.save()
        newCategoryName = ""
    }
}

// MARK: - Manage categories sheet

/// Full management UI: create (name + icon), rename, re-style, delete with
/// confirmation that reports how many scripts will be uncategorized.
struct ManageCategoriesSheet: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Query(sort: \ScriptCategory.createdAt)
    private var categories: [ScriptCategory]

    @State private var newName = ""
    @State private var newSymbol = CategoryStyle.tag
    @State private var editing: ScriptCategory?
    @State private var deleteTarget: ScriptCategory?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if categories.isEmpty {
                    ContentUnavailableView {
                        Label("No Categories", systemImage: "tray")
                    } description: {
                        Text("Create a category to group related scripts.")
                    }
                } else {
                    List {
                        ForEach(categories) { category in
                            Button {
                                editing = category
                            } label: {
                                HStack(spacing: 12) {
                                    CategoryIconView(symbolName: category.symbolName)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(category.name)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text("\(category.scripts.count) scripts")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "info.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget = category
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                CategoryCreateBar(
                    name: $newName,
                    symbol: $newSymbol,
                    onSubmit: createCategory
                )
            }
            .sheet(item: $editing) { category in
                CategoryEditSheet(
                    category: category,
                    onSave: { name, symbol in
                        renameCategory(category, to: name, symbol: symbol)
                    },
                    onCancel: { editing = nil }
                )
            }
            .confirmationDialog(
                "Delete “\(deleteTarget?.name ?? "")”?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Category", role: .destructive) {
                    if let category = deleteTarget {
                        performDelete(category)
                    }
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                if let count = deleteTarget?.scripts.count, count > 0 {
                    Text("\(count) script\(count == 1 ? "" : "s") will become uncategorized. They won't be deleted.")
                } else {
                    Text("This category is empty.")
                }
            }
        }
    }

    // MARK: - Actions

    private func createCategory() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let category = ScriptCategory(name: trimmed, symbolName: newSymbol.rawValue)
        modelContext.insert(category)
        try? modelContext.save()
        newName = ""
        newSymbol = .tag
    }

    private func renameCategory(_ category: ScriptCategory, to name: String, symbol: CategoryStyle) {
        category.name = name
        category.symbolName = symbol.rawValue
        try? modelContext.save()
        editing = nil
    }

    private func performDelete(_ category: ScriptCategory) {
        modelContext.delete(category)
        try? modelContext.save()
        deleteTarget = nil
    }
}

// MARK: - Create bar

/// Bottom input row for creating a category with an icon menu.
struct CategoryCreateBar: View {
    @Binding var name: String
    @Binding var symbol: CategoryStyle
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(CategoryStyle.allCases) { style in
                    Button {
                        symbol = style
                    } label: {
                        if symbol == style {
                            Label(style.menuLabelText, systemImage: "checkmark")
                        } else {
                            Label(style.menuLabelText, systemImage: style.symbolName)
                        }
                    }
                }
            } label: {
                symbol.icon
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .accessibilityLabel("Category icon")

            TextField("New category name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Edit sheet

/// Rename + restyle an existing category. Owns a local draft so Cancel
/// discards cleanly without touching the live model object.
struct CategoryEditSheet: View {
    let category: ScriptCategory
    var onSave: (String, CategoryStyle) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var symbol: CategoryStyle

    init(
        category: ScriptCategory,
        onSave: @escaping (String, CategoryStyle) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.category = category
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: category.name)
        _symbol = State(initialValue: CategoryStyle(rawValue: category.symbolName) ?? .tag)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                }
                Section("Icon") {
                    Picker("Icon", selection: $symbol) {
                        ForEach(CategoryStyle.allCases) { style in
                            HStack(spacing: 8) {
                                style.icon
                                Text(style.menuLabelText)
                            }
                            .tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(trimmedName, symbol) }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}

extension CategoryStyle {
    /// Human label for menus.
    var menuLabelText: String {
        switch self {
        case .tag: "Tag"
        case .folder: "Folder"
        case .briefcase: "Briefcase"
        case .sparkles: "Sparkles"
        case .flame: "Flame"
        case .star: "Star"
        case .globe: "Globe"
        case .graduationCap: "Graduation Cap"
        case .bubble: "Speech"
        case .wand: "Magic"
        }
    }
}
