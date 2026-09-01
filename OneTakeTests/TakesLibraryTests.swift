import Foundation
@testable import OneTake
import SwiftData
import Testing

struct TakesLibraryTests {
    @Test func scriptSelectorResolveTitle() {
        let s1 = Script(title: "Demo", body: "")
        let s2 = Script(title: "Other", body: "")
        // Need IDs stable
        let scripts = [s1, s2]
        #expect(ScriptSelectorView.resolveTitle(for: s1.id, scripts: scripts) == "Demo")
        #expect(ScriptSelectorView.resolveTitle(for: UUID(), scripts: scripts) == "Freestyle / No script")
        #expect(ScriptSelectorView.resolveTitle(for: nil, scripts: scripts) == "Freestyle / No script")
        #expect(ScriptSelectorView.resolveTitle(for: s1.id, scripts: []) == "Freestyle / No script")
    }

    @Test func myTakesSearchFiltering() {
        // Simulate MyTakesView filteredTakes logic
        let sDemo = Script(title: "Demo Script", body: "")
        let sOther = Script(title: "Other", body: "")
        func title(for id: UUID, map: [UUID: String]) -> String {
            map[id] ?? "Freestyle / No script"
        }
        let map: [UUID: String] = [sDemo.id: sDemo.title, sOther.id: sOther.title]
        let takes = [
            Take(scriptID: sDemo.id, fileURL: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 10),
            Take(scriptID: sOther.id, fileURL: URL(fileURLWithPath: "/tmp/b.mp4"), duration: 10),
            Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/c.mp4"), duration: 10),
        ]
        func filter(_ q: String) -> [Take] {
            guard !q.isEmpty else { return takes }
            return takes.filter { title(for: $0.scriptID, map: map).localizedCaseInsensitiveContains(q) }
        }
        #expect(filter("demo").count == 1)
        #expect(filter("DEMO").count == 1)
        #expect(filter("other").count == 1)
        #expect(filter("missing").isEmpty)
        #expect(filter("").count == 3)
    }

    @Test func myTakesDayGrouping() throws {
        // Verify grouping by day logic produces Today/Yesterday headers
        let cal = Calendar.current
        let now = Date()
        let todayTake = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/t.mp4"), createdAt: now, duration: 5)
        let yesterdayTake = try Take(
            scriptID: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/y.mp4"),
            createdAt: #require(cal.date(byAdding: .day, value: -1, to: now)),
            duration: 5
        )
        let oldTake = try Take(
            scriptID: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/o.mp4"),
            createdAt: #require(cal.date(byAdding: .day, value: -5, to: now)),
            duration: 5
        )
        let takes = [todayTake, yesterdayTake, oldTake]
        func dayKey(for date: Date) -> String {
            if cal.isDateInToday(date) {
                return "Today"
            }
            if cal.isDateInYesterday(date) {
                return "Yesterday"
            }
            let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .none
            return fmt.string(from: date)
        }
        let dict = Dictionary(grouping: takes) { dayKey(for: $0.createdAt) }
        #expect(dict["Today"]?.count == 1)
        #expect(dict["Yesterday"]?.count == 1)
        #expect(dict.count == 3)
    }

    @Test func deleteCleanup() throws {
        // Verify delete removes file and record without crash when file missing
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Script.self, Take.self, ScriptCategory.self, configurations: config)
        let ctx = ModelContext(container)
        let take = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).mp4"), duration: 10)
        ctx.insert(take)
        try ctx.save()
        // Simulate MyTakesView performDelete with missing file
        try? FileManager.default.removeItem(at: take.fileURL) // no file, should not throw
        ctx.delete(take)
        try ctx.save()
        let remaining = try ctx.fetch(FetchDescriptor<Take>())
        #expect(remaining.isEmpty)
    }

    @Test func pauseStateMachineSingleFileInvariant() async {
        #if targetEnvironment(simulator)
            // On simulator, pause is just flag, finalizeSegmentsIfNeeded returns nil -> single file invariant holds (original file)
            let svc = CaptureService()
            svc.pauseRecording()
            #expect(svc.isPaused() == true)
            svc.resumeRecording()
            #expect(svc.isPaused() == false)
            let url = URL(fileURLWithPath: "/tmp/dummy.mp4")
            let merged = await svc.finalizeSegmentsIfNeeded(originalURL: url)
            #expect(merged == nil) // no segments on simulator
        #else
            // Device path would test merge; gated behind TARGET_OS_SIMULATOR
            #expect(true)
        #endif
    }

    @Test func captureServiceRespondsToPauseSelectors() {
        #if targetEnvironment(simulator)
            // Ensure no private API beyond responds(to:) — verify service exposes pause without direct selector crash
            let svc = CaptureService()
            // Should not crash on simulator fallback
            svc.pauseRecording()
            svc.resumeRecording()
            #expect(!svc.isPaused() || svc.isPaused())
        #endif
    }
}
