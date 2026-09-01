//
//  ScriptSelectorView.swift
//  OneTake
//

import SwiftData
import SwiftUI

///
///  ScriptSelectorView.swift
///  OneTake
///
///  Top-bar script picker for Studio — lists all scripts plus freestyle.
///  Instantly swaps `PrompterView` text without restarting `AVCaptureSession`.
///  Persists to `@AppStorage("lastScriptID")`; falls back to “No script” with
///  transient indicator when the ID is deleted.
///
struct ScriptSelectorView: View {
    @Query(sort: \Script.updatedAt, order: .reverse)
    private var scripts: [Script]
    @Query(sort: \ScriptCategory.createdAt)
    private var categories: [ScriptCategory]
    @Binding var selectedID: Script.ID?
    @State private var showMissing = false

    /// Scripts grouped by category, in category creation order; uncategorized
    /// scripts render in a trailing "No category" section.
    private var groupedEntries: [(title: String, items: [Script])] {
        var entries: [(String, [Script])] = []
        for category in categories {
            let members = scripts.filter { $0.category?.id == category.id }
            if !members.isEmpty {
                entries.append((category.name, members))
            }
        }
        let loose = scripts.filter { $0.category == nil }
        if !loose.isEmpty {
            entries.append(("No category", loose))
        }
        return entries
    }

    var body: some View {
        Menu {
            Button {
                selectedID = nil
                UserDefaults.standard.removeObject(forKey: "lastScriptID")
            } label: {
                Label("No script — Freestyle", systemImage: selectedID == nil ? "checkmark" : "doc")
            }
            if !scripts.isEmpty {
                Divider()
            }
            ForEach(groupedEntries, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { script in
                        scriptButton(for: script)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                Text(currentTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.black.opacity(0.55), in: Capsule())
        }
        .accessibilityLabel("Select script")
        .overlay(alignment: .top) {
            if showMissing {
                Text("Script not available").font(.caption2.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Color.red, in: Capsule())
                    .offset(y: 36).transition(.opacity)
            }
        }
        .onAppear {
            // Restore last selection; fallback to nil if missing
            if let str = UserDefaults.standard.string(forKey: "lastScriptID"), let uuid = UUID(uuidString: str) {
                if scripts.contains(where: { $0.id == uuid }) {
                    selectedID = uuid
                } else {
                    selectedID = nil
                    if str.isEmpty == false {
                        withAnimation { showMissing = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showMissing = false } }
                    }
                }
            }
        }
        .onChange(of: selectedID) { _, new in
            if let id = new {
                UserDefaults.standard.set(id.uuidString, forKey: "lastScriptID")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastScriptID")
            }
        }
    }

    // swiftlint:disable:next avoid_helper_func_view
    private func scriptButton(for script: Script) -> some View {
        Button {
            selectedID = script.id
            UserDefaults.standard.set(script.id.uuidString, forKey: "lastScriptID")
        } label: {
            Label(
                script.title.isEmpty ? "Untitled" : script.title,
                systemImage: selectedID == script.id ? "checkmark" : "doc.text"
            )
        }
    }

    private var currentTitle: String {
        guard let id = selectedID, let s = scripts.first(where: { $0.id == id }) else { return "No script" }
        return s.title.isEmpty ? "Untitled" : s.title
    }

    static func resolveTitle(for id: Script.ID?, scripts: [Script]) -> String {
        guard let id else { return "Freestyle / No script" }
        return scripts.first(where: { $0.id == id })?.title ?? "Freestyle / No script"
    }
}

#Preview {
    ScriptSelectorView(selectedID: .constant(nil))
        .modelContainer(for: [Script.self, Take.self, ScriptCategory.self], inMemory: true)
        .padding().background(Color.black)
}
