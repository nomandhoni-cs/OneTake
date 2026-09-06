import Foundation
@testable import OneTake
import SwiftData
import Testing

struct ReactionModelTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Script.self, Take.self, ScriptCategory.self, configurations: config)
        return ModelContext(container)
    }

    @Test func newTakeDefaultsToNonReaction() throws {
        let ctx = try makeContext()
        let take = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 20)
        #expect(take.isReaction == false)
        #expect(take.backgroundAssetLocalID == nil)
        ctx.insert(take)
        try ctx.save()

        let fetched = try #require(ctx.fetch(FetchDescriptor<Take>()).first)
        #expect(fetched.isReaction == false)
        #expect(fetched.backgroundAssetLocalID == nil)
    }

    @Test func reactionTakeRoundTripsFlagAndBackgroundID() throws {
        let ctx = try makeContext()
        let take = Take(
            scriptID: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/r.mp4"),
            duration: 30,
            isReaction: true,
            backgroundAssetLocalID: "ABC-123"
        )
        ctx.insert(take)
        try ctx.save()

        let fetched = try #require(ctx.fetch(FetchDescriptor<Take>()).first)
        #expect(fetched.isReaction == true)
        #expect(fetched.backgroundAssetLocalID == "ABC-123")
        // Downstream pipeline treats it as a normal take.
        #expect(fetched.bladeSegments().count == 1)
    }
}
