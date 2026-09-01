import Foundation
@testable import OneTake
import SwiftData
import Testing

// MARK: - Script categories

struct ScriptCategoryTests {
    /// In-memory container with all three models — mirrors the app schema.
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Script.self, Take.self, ScriptCategory.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func assignAndQueryByCategory() throws {
        let ctx = try makeContext()
        let youtube = ScriptCategory(name: "YouTube", symbolName: "flame")
        let pitch = ScriptCategory(name: "Pitches", symbolName: "briefcase")
        ctx.insert(youtube)
        ctx.insert(pitch)

        let a = Script(title: "A", body: "x", category: youtube)
        let b = Script(title: "B", body: "x", category: youtube)
        let c = Script(title: "C", body: "x", category: pitch)
        ctx.insert(a)
        ctx.insert(b)
        ctx.insert(c)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Script>())
        #expect(all.count == 3)

        // Relationship from both directions
        #expect(youtube.scripts.count == 2)
        #expect(pitch.scripts.count == 1)
        #expect(a.category?.name == "YouTube")

        // Filter (the library's visibleScripts logic) — fetch order is not
        // guaranteed, so compare as sets.
        let filtered = all.filter { $0.category?.id == youtube.id }
        #expect(Set(filtered.map(\.title)) == Set(["A", "B"]))
    }

    @Test func renamePropagatesToScripts() throws {
        let ctx = try makeContext()
        let category = ScriptCategory(name: "Drafts", symbolName: "folder")
        ctx.insert(category)
        let script = Script(title: "S", body: "x", category: category)
        ctx.insert(script)
        try ctx.save()

        category.name = "Final"
        try ctx.save()

        #expect(script.category?.name == "Final")
        // No duplicate spelling appears — one entity, one query hit
        let all = try ctx.fetch(FetchDescriptor<ScriptCategory>())
        #expect(all.count == 1)
        #expect(all.first?.name == "Final")
    }

    @Test func deleteCategoryNullifiesScriptCategory() throws {
        let ctx = try makeContext()
        let category = ScriptCategory(name: "Temp", symbolName: "tag")
        ctx.insert(category)
        let script = Script(title: "S", body: "x", category: category)
        ctx.insert(script)
        try ctx.save()

        ctx.delete(category)
        try ctx.save()

        // Script survives, uncategorized
        let scripts = try ctx.fetch(FetchDescriptor<Script>())
        #expect(scripts.count == 1)
        #expect(scripts.first?.category == nil)
    }

    @Test func deleteScriptLeavesCategoryIntact() throws {
        let ctx = try makeContext()
        let category = ScriptCategory(name: "Keep", symbolName: "star")
        ctx.insert(category)
        let script = Script(title: "S", body: "x", category: category)
        ctx.insert(script)
        try ctx.save()

        ctx.delete(script)
        try ctx.save()

        let categories = try ctx.fetch(FetchDescriptor<ScriptCategory>())
        #expect(categories.count == 1)
        #expect(categories.first?.scripts.isEmpty == true)
    }

    @Test func duplicateCarriesCategory() throws {
        let ctx = try makeContext()
        let category = ScriptCategory(name: "Ads", symbolName: "sparkles")
        ctx.insert(category)
        let original = Script(title: "Original", body: "x", category: category)
        ctx.insert(original)
        try ctx.save()

        // Mirrors ScriptLibraryView.duplicate
        let copy = Script(
            title: original.title + " copy",
            body: original.body,
            category: original.category
        )
        ctx.insert(copy)
        try ctx.save()

        #expect(copy.category?.id == category.id)
        #expect(category.scripts.count == 2)
    }

    @Test func displayTitleFallback() {
        #expect(Script(title: "", body: "x").displayTitle == "Untitled")
        #expect(Script(title: "   ", body: "x").displayTitle == "Untitled")
        #expect(Script(title: "Named", body: "x").displayTitle == "Named")
    }

    // MARK: - Library filter + sort semantics

    @Test func libraryFilterAndSortLogic() throws {
        let ctx = try makeContext()
        let catA = ScriptCategory(name: "A", symbolName: "tag")
        let catB = ScriptCategory(name: "B", symbolName: "star")
        ctx.insert(catA)
        ctx.insert(catB)

        let old = Date.distantPast
        let s1 = Script(title: "Zeta", body: "z", createdAt: old, updatedAt: old, category: catA)
        let s2 = Script(title: "alpha", body: "a", createdAt: Date(), updatedAt: Date(), category: catA)
        let s3 = Script(title: "Mid", body: "m", category: catB)
        [s1, s2, s3].forEach { ctx.insert($0) }
        try ctx.save()

        let scripts = try ctx.fetch(FetchDescriptor<Script>())

        // Filter by catA
        let inA = scripts.filter { $0.category?.id == catA.id }
        #expect(Set(inA.map(\.title)) == Set(["Zeta", "alpha"]))

        // Sort by title, case-insensitive (library sortMode == .title)
        let byTitle = inA
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            .map(\.displayTitle)
        #expect(byTitle == ["alpha", "Zeta"])

        // Sort by updatedAt (library default) — newest first
        let byUpdated = scripts
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { $0.category?.id == catA.id }
            .map(\.title)
        #expect(byUpdated.first == "alpha")

        // Uncategorized grouping: s3 has a category, so uncategorized is empty
        #expect(scripts.filter { $0.category == nil }.isEmpty)

        // Filter chip count for catA
        var counts: [UUID: Int] = [:]
        for script in scripts {
            guard let id = script.category?.id else { continue }
            counts[id, default: 0] += 1
        }
        #expect(counts[catA.id] == 2)
        #expect(counts[catB.id] == 1)
    }

    @Test func categoryStyleSymbolMapping() {
        // Every style maps to an SF Symbol name
        for style in CategoryStyle.allCases {
            #expect(!style.symbolName.isEmpty)
        }
        #expect(CategoryStyle(rawValue: "flame") == .flame)
        #expect(CategoryStyle(rawValue: "nope") == nil)
        #expect(CategoryStyle.allCases.count == 10)
    }

    @Test func menuLabelsHumanReadable() {
        #expect(CategoryStyle.graduationCap.menuLabelText == "Graduation Cap")
        #expect(CategoryStyle.bubble.menuLabelText == "Speech")
        #expect(CategoryStyle.wand.menuLabelText == "Magic")
        #expect(Set(CategoryStyle.allCases.map(\.menuLabelText)).count == CategoryStyle.allCases.count)
    }
}
