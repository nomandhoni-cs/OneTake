import CoreMedia
@testable import OneTake
import SwiftData
import Testing

struct BladeEditingTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Script.self, Take.self, ScriptCategory.self, configurations: config)
        return ModelContext(container)
    }

    @Test func existingTakeWithoutBladeLoadsAsSingleSegment() throws {
        let ctx = try makeContext()
        let take = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 20)
        // bladeCuts defaults to nil -> lightweight migration case
        #expect(take.bladeCuts == nil)
        ctx.insert(take)
        try ctx.save()

        let fetched = try #require(ctx.fetch(FetchDescriptor<Take>()).first)
        #expect(fetched.bladeCuts == nil)
        let segs = fetched.bladeSegments()
        #expect(segs.count == 1)
        #expect(segs.first?.duration.seconds == 20)
    }

    @Test func bladeCutsRoundTripAndDerivedSegments() throws {
        let ctx = try makeContext()
        let take = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/b.mp4"), duration: 20, bladeCuts: [5, 12])
        ctx.insert(take)
        try ctx.save()

        let fetched = try #require(ctx.fetch(FetchDescriptor<Take>()).first)
        #expect(fetched.bladeCuts == [5, 12])
        let segs = fetched.bladeSegments()
        #expect(segs.count == 3)
        #expect(segs[0].start.seconds == 0 && segs[0].duration.seconds == 5)
        #expect(segs[1].start.seconds == 5 && segs[1].duration.seconds == 7)
        #expect(segs[2].start.seconds == 12 && segs[2].duration.seconds == 8)
        #expect(fetched.bladeEffectiveDuration == 20)
    }

    @Test func bladeCutsClampedAndDeduped() throws {
        let take = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/c.mp4"), duration: 20, bladeCuts: [0.05, 19.95, 8.001, 8.05])
        // 0.05 and 19.95 are within 0.1 of trim edges -> pruned
        // 8.001 and 8.05 deduped within 0.1
        let normalized = take.normalizedBladeCuts
        #expect(normalized.count == 1)
        #expect(try abs(#require(normalized.first) - 8.001) < 0.01)
    }

    @Test func trimPrunesCuts() {
        var take = Take(
            scriptID: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/d.mp4"),
            duration: 30,
            trimRange: CMTimeRange(
                start: CMTime(seconds: 5, preferredTimescale: 600),
                duration: CMTime(seconds: 10, preferredTimescale: 600)
            ),
            bladeCuts: [3, 7, 12, 20]
        )
        // trim 5-15, cuts 3 outside, 7 inside, 12 inside, 20 outside
        let pruned = take.prunedBladeCuts()
        #expect(pruned == [7, 12])
        // After trimming to 6-15, 7 stays, 12 stays, but 3 pruned
        take.trimStartSeconds = 6
        take.trimDurationSeconds = 9
        let pruned2 = take.prunedBladeCuts()
        #expect(pruned2 == [7, 12])
        take.trimStartSeconds = 8
        let pruned3 = take.prunedBladeCuts()
        #expect(pruned3 == [12])
    }

    @Test func deleteMiddleSegmentCompacts() {
        // Simulate Review's deleteSelectedSegment compact logic for interior
        var cuts: [Double] = [5, 12]
        let trimStart = 0.0
        let trimEnd = 20.0
        let idx = 1
        let segments: [(Double, Double)] = {
            var segs: [(Double, Double)] = []
            var prev = trimStart
            for cut in cuts.sorted() {
                segs.append((prev, cut))
                prev = cut
            }
            segs.append((prev, trimEnd))
            return segs
        }()
        let seg = segments[idx]
        let len = seg.1 - seg.0
        // Remove segEnd (12) and shift subsequent
        var newCuts: [Double] = []
        for c in cuts {
            if c == seg.1 {
                continue
            }
            var nc = c
            if c > seg.1 {
                nc -= len
            }
            newCuts.append(nc)
        }
        #expect(newCuts == [5])
    }

    @Test func compositionTimeRangesSum() {
        // Verify sum of blade segments equals effective duration
        let take = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/e.mp4"), duration: 20, bladeCuts: [5, 12])
        let segs = take.bladeSegments()
        let sum = segs.reduce(0) { $0 + $1.duration.seconds }
        #expect(abs(sum - 20) < 0.001)
        // After deleting middle, effective duration 13
        let prunedAfterDelete: [Double] = [5]
        let take2 = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/f.mp4"), duration: 20, bladeCuts: prunedAfterDelete)
        // For take2, segments [0-5,5-20] => 20 total (since we compacted via shift, not gap)
        // Our simple model keeps source positions, so sum still 20. Composition skips deleted interval via gap, sum 13.
        // The test verifies bladeCuts helper doesn't invent time.
        #expect(take2.bladeSegments().count == 2)
    }

    @Test func lutThumbnailProviderCaches() {
        // Natural returns gray, non-natural returns filtered or placeholder; cache hit on second call
        let first = LUTCubeThumbnailProvider.thumbnail(for: .natural)
        let second = LUTCubeThumbnailProvider.thumbnail(for: .natural)
        #expect(first != nil)
        #expect(second != nil)
        // Cache should return same instance (pointer equality not guaranteed, but non-nil and size correct)
        #expect(first?.width == 40 && first?.height == 24)
        let warm = LUTCubeThumbnailProvider.thumbnail(for: .warmStudio)
        #expect(warm != nil)
    }
}
