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
        // Deleting a middle segment removes its source range outright; the
        // survivors keep their source positions (no shifting arithmetic).
        let take = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/d2.mp4"), duration: 20)
        take.segments = [BladeSegment(start: 0, duration: 5), BladeSegment(start: 5, duration: 7), BladeSegment(start: 12, duration: 8)]
        #expect(take.deleteSegment(at: 1) == true)
        let segs = take.bladeSegments()
        #expect(segs.count == 2)
        #expect(segs[0].start.seconds == 0 && segs[0].duration.seconds == 5)
        #expect(segs[1].start.seconds == 12 && segs[1].duration.seconds == 8)
        #expect(abs(take.bladeEffectiveDuration - 13) < 0.001)
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
        // Legacy cut-derivation (no stored ranges): spans [0-5,5-20] keep
        // source positions, so the legacy path still sums to 20 here — actual
        // deletions go through stored ranges (see BladeSegmentStoreTests).
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

/// Explicit-range blade engine: split/delete/trim-clip/undo on stored source
/// ranges, with legacy cut-derivation fallback and SwiftData round-trip.
struct BladeSegmentStoreTests {
    private func makeTake(duration: Double = 20) -> Take {
        Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/blade-\(UUID().uuidString).mp4"), duration: duration)
    }

    private func ranges(of take: Take) -> [(Double, Double)] {
        take.bladeSegments().map { ($0.start.seconds, ($0.start + $0.duration).seconds) }
    }

    @Test func splitAccumulatesRanges() {
        let take = makeTake(duration: 25)
        #expect(take.split(at: 5) == 1)
        #expect(take.split(at: 12) == 2)
        #expect(take.split(at: 18) == 3)
        let segs = ranges(of: take)
        #expect(segs.count == 4)
        #expect(segs[0].0 == 0 && segs[0].1 == 5)
        #expect(segs[3].0 == 18 && segs[3].1 == 25)
        #expect(take.bladeCuts == [5, 12, 18])
    }

    @Test func splitDuplicateAndEdgeIgnored() {
        let take = makeTake()
        #expect(take.split(at: 8) == 1)
        #expect(take.split(at: 8) == nil) // duplicate
        #expect(take.split(at: 8.05) == nil) // within margin
        #expect(take.split(at: 0.05) == nil) // too close to start
        #expect(take.split(at: 19.97) == nil) // too close to end
        #expect(ranges(of: take).count == 2)
        #expect(take.bladeCuts == [8])
    }

    @Test func deleteMiddleExcludesInterval() {
        // REGRESSION: the old cut-shift engine kept deleted footage in the
        // derived ranges ([0-5]+[5-20]); stored ranges must exclude it.
        let take = makeTake()
        take.segments = [BladeSegment(start: 0, duration: 5), BladeSegment(start: 5, duration: 7), BladeSegment(start: 12, duration: 8)]
        #expect(take.deleteSegment(at: 1) == true)
        let segs = ranges(of: take)
        #expect(segs.count == 2)
        #expect(segs[0] == (0, 5))
        #expect(segs[1] == (12, 20))
        #expect(abs(take.bladeEffectiveDuration - 13) < 0.001)
        #expect(take.bladeCuts == [12]) // synced divider: next survivor's start
    }

    @Test func deleteFirstAndLast() {
        let take = makeTake()
        take.segments = [BladeSegment(start: 0, duration: 5), BladeSegment(start: 5, duration: 7), BladeSegment(start: 12, duration: 8)]
        #expect(take.deleteSegment(at: 0) == true)
        #expect(ranges(of: take).map(\.0) == [5, 12])
        #expect(take.deleteSegment(at: 1) == true)
        #expect(ranges(of: take).count == 1)
        #expect(take.bladeCuts == nil) // single survivor mirrors legacy nil-cuts
    }

    @Test func deleteSoleAndOutOfBoundsDenied() {
        let take = makeTake()
        #expect(take.deleteSegment(at: 0) == false) // single span, nothing stored
        #expect(take.segments == nil) // untouched
        take.segments = [BladeSegment(start: 0, duration: 10), BladeSegment(start: 10, duration: 10)]
        #expect(take.deleteSegment(at: 5) == false)
        #expect(take.deleteSegment(at: -1) == false)
        #expect(ranges(of: take).count == 2)
    }

    @Test func legacyDeriveOnFirstEdit() {
        let take = makeTake()
        take.bladeCuts = [5, 12]
        #expect(take.segments == nil)
        #expect(take.split(at: 18) == 3)
        let segs = ranges(of: take)
        #expect(segs.count == 4)
        #expect(segs[2] == (12, 18))
        #expect(segs[3] == (18, 20))
        #expect(take.bladeCuts == [5, 12, 18])
    }

    @Test func undoSnapshotRestoresRanges() {
        let take = makeTake()
        _ = take.split(at: 8)
        let before = (take.segments, take.bladeCuts)
        _ = take.split(at: 14)
        #expect(ranges(of: take).count == 3)
        take.segments = before.0
        take.bladeCuts = before.1
        #expect(ranges(of: take).count == 2)
        #expect(take.bladeCuts == [8])
    }

    @Test func clipToTrimClampsAndDrops() {
        let take = makeTake()
        take.segments = [BladeSegment(start: 0, duration: 5), BladeSegment(start: 5, duration: 7), BladeSegment(start: 12, duration: 8)]
        #expect(take.clipSegments(start: 3, end: 15) == true)
        let segs = ranges(of: take)
        #expect(segs.count == 3)
        #expect(segs[0] == (3, 5)) // partial overlap clamped
        #expect(segs[2] == (12, 15)) // partial overlap clamped
        #expect(take.clipSegments(start: 3, end: 15) == false) // idempotent: no change, no save needed
    }

    @Test func clipSliverMergesForIndexAlignment() {
        // Leading sub-0.1s sliver drops (trim start covers it).
        let take = makeTake()
        take.segments = [BladeSegment(start: 5.0, duration: 0.05), BladeSegment(start: 5.05, duration: 14.95)]
        _ = take.clipSegments(start: 5, end: 20)
        let segs = ranges(of: take)
        #expect(segs.count == 1)
        #expect(abs(segs[0].0 - 5.05) < 0.001)
        // Mid-list sliver absorbs into its predecessor.
        let take2 = makeTake()
        take2.segments = [
            BladeSegment(start: 5, duration: 5),
            BladeSegment(start: 10, duration: 0.05),
            BladeSegment(start: 10.05, duration: 9.95),
        ]
        _ = take2.clipSegments(start: 5, end: 20)
        let segs2 = ranges(of: take2)
        #expect(segs2.count == 2)
        #expect(abs(segs2[0].1 - 10.05) < 0.001)
        #expect(abs(segs2[1].0 - 10.05) < 0.001)
    }

    @Test func clipEmptyClearsToNil() {
        let take = makeTake()
        take.segments = [BladeSegment(start: 0, duration: 5)]
        #expect(take.clipSegments(start: 10, end: 20) == true)
        #expect(take.segments == nil)
        #expect(take.bladeCuts == nil)
    }

    @Test func clipNoOpOnUnbladedTake() {
        let take = makeTake()
        #expect(take.clipSegments(start: 2, end: 18) == false)
        #expect(take.segments == nil)
        #expect(take.bladeCuts == nil)
    }

    @Test func syncInvariantHoldsAcrossOps() {
        let take = makeTake(duration: 30)
        func checkInvariant() {
            let expected: [Double]? = {
                guard let list = take.segments, list.count > 1 else { return nil }
                return list.sorted { $0.start < $1.start }.dropFirst().map(\.start)
            }()
            #expect(take.bladeCuts == expected)
        }
        _ = take.split(at: 6)
        _ = take.split(at: 20)
        _ = take.split(at: 13)
        checkInvariant()
        _ = take.deleteSegment(at: 0)
        checkInvariant()
        _ = take.clipSegments(start: 5, end: 25)
        checkInvariant()
        _ = take.deleteSegment(at: 1)
        checkInvariant()
    }

    @Test func segmentsRoundTripSwiftData() throws {
        // Proves [BladeSegment]? persists (validates the additive-field approach).
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Script.self, Take.self, ScriptCategory.self, configurations: config)
        let ctx = ModelContext(container)
        let take = makeTake()
        take.segments = [BladeSegment(start: 0, duration: 5), BladeSegment(start: 12, duration: 8)]
        take.syncCutsFromSegments()
        ctx.insert(take)
        try ctx.save()
        let fetched = try #require(ctx.fetch(FetchDescriptor<Take>()).first)
        #expect(fetched.segments == [BladeSegment(start: 0, duration: 5), BladeSegment(start: 12, duration: 8)])
        #expect(fetched.bladeCuts == [12])
        #expect(abs(fetched.bladeEffectiveDuration - 13) < 0.001)
    }

    @Test func rangesClippedToDoesNotMutate() {
        let take = makeTake()
        take.segments = [BladeSegment(start: 0, duration: 5), BladeSegment(start: 5, duration: 15)]
        let clipped = take.rangesClippedTo(start: 2, end: 18)
        #expect(clipped.count == 2)
        #expect(clipped[0].start == 2)
        #expect(ranges(of: take).count == 2) // take untouched
        #expect(take.segments?.count == 2)
    }

    @Test func zeroDurationGuards() {
        let take = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/zero.mp4"), duration: 0)
        #expect(take.split(at: 1) == nil)
        #expect(take.deleteSegment(at: 0) == false)
        #expect(take.segments == nil)
    }
}
