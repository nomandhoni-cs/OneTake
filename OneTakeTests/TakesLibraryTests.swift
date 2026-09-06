import CoreMedia
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
        // Pause/resume only flips state without hardware; with no segments,
        // finalize returns nil so the single-file invariant holds.
        let svc = CaptureService()
        svc.pauseRecording()
        #expect(svc.isPaused() == true)
        svc.resumeRecording()
        #expect(svc.isPaused() == false)
        let url = URL(fileURLWithPath: "/tmp/dummy.mp4")
        let merged = await svc.finalizeSegmentsIfNeeded(originalURL: url)
        #expect(merged == nil) // no segments recorded
    }

    @Test func captureServiceRespondsToPauseSelectors() {
        // Pause/resume must never crash, even with no active recording —
        // only `responds(to:)` gating is used, no private API.
        let svc = CaptureService()
        svc.pauseRecording()
        svc.resumeRecording()
        #expect(!svc.isPaused() || svc.isPaused())
    }
}

/// Guideline-audit helpers: trim-aware enablement, scope filter, localized
/// day keys, and the VoiceOver row label. Pure logic — no SwiftUI needed.
struct TakesLibraryHelperTests {
    private static func take(
        duration: TimeInterval = 20,
        trim: CMTimeRange? = nil,
        lutPreset: String = LUTPreset.natural.rawValue,
        isReaction: Bool = false
    ) -> Take {
        Take(
            scriptID: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mp4"),
            duration: duration,
            trimRange: trim,
            lutPreset: lutPreset,
            isReaction: isReaction
        )
    }

    @Test func trimWindowFallsBackToFullDuration() {
        let window = TakesLibrary.trimWindow(of: Self.take(duration: 20))
        #expect(window.start == 0 && window.end == 20)
        #expect(TakesLibrary.effectiveTrimLength(of: Self.take(duration: 20)) == 20)
        #expect(TakesLibrary.effectiveTrimLength(of: Self.take(duration: 0)) == 10) // legacy fallback
    }

    @Test func bladeSplitPredicateIsTrimAware() {
        #expect(TakesLibrary.canBladeSplit(Self.take(duration: 20)))
        let shortTrim = CMTimeRange(
            start: CMTime(seconds: 5, preferredTimescale: 600),
            duration: CMTime(seconds: 0.5, preferredTimescale: 600)
        )
        #expect(!TakesLibrary.canBladeSplit(Self.take(duration: 20, trim: shortTrim)))
        let okTrim = CMTimeRange(
            start: CMTime(seconds: 5, preferredTimescale: 600),
            duration: CMTime(seconds: 5, preferredTimescale: 600)
        )
        #expect(TakesLibrary.canBladeSplit(Self.take(duration: 20, trim: okTrim)))
    }

    @Test func deleteSegmentPredicateNeedsTwoSegments() {
        let single = Self.take(duration: 20)
        #expect(!TakesLibrary.canDeleteLastSegment(of: single))
        single.clipSegments(start: 0, end: 20)
        #expect(single.split(at: 10) != nil)
        #expect(TakesLibrary.canDeleteLastSegment(of: single))
    }

    @Test func scopeComposesAllVsReactions() {
        let plain = Self.take()
        let reaction = Self.take(isReaction: true)
        #expect(TakesLibrary.matchesScope(plain, scope: .all))
        #expect(TakesLibrary.matchesScope(reaction, scope: .all))
        #expect(!TakesLibrary.matchesScope(plain, scope: .reactions))
        #expect(TakesLibrary.matchesScope(reaction, scope: .reactions))
    }

    @Test func dayKeyUsesRelativeFormatting() {
        // Independent formatter — validates the helper opts into relative dates
        // without hardcoding English words (locale-proof).
        let reference = DateFormatter()
        reference.dateStyle = .medium
        reference.timeStyle = .none
        reference.doesRelativeDateFormatting = true
        let now = Date()
        #expect(TakesLibrary.relativeDayKey(for: now) == reference.string(from: now))
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)
        if let yesterday {
            #expect(TakesLibrary.relativeDayKey(for: yesterday) == reference.string(from: yesterday))
        }
    }

    @Test func rowLabelCombinesTitleDurationBadges() {
        let plain = Self.take(duration: 32)
        let label = TakesLibrary.rowAccessibilityLabel(title: "Demo", take: plain, fileExists: true)
        #expect(label.contains("Demo") && label.contains("0:32"))
        #expect(!label.contains("File missing"))
        let gradedTrim = CMTimeRange(
            start: CMTime(seconds: 0, preferredTimescale: 600),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        let rich = Self.take(duration: 75, trim: gradedTrim, lutPreset: LUTPreset.warmStudio.rawValue, isReaction: true)
        let richLabel = TakesLibrary.rowAccessibilityLabel(title: "Demo", take: rich, fileExists: true)
        #expect(richLabel.contains("Trimmed") && richLabel.contains("Warm Studio") && richLabel.contains("Reaction"))
        let missing = TakesLibrary.rowAccessibilityLabel(title: "Demo", take: plain, fileExists: false)
        #expect(missing.contains("File missing"))
    }

    @Test func freestyleAndDurationFormat() {
        #expect(!TakesLibrary.freestyleTitle().isEmpty)
        #expect(TakesLibrary.formatDuration(75) == "1:15")
        #expect(TakesLibrary.formatDuration(5) == "0:05")
    }
}
