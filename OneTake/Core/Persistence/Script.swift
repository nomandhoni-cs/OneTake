//
//  Script.swift
//  OneTake
//

//  See: docs/ARCHITECTURE.md §5 (Persistence) + openspec/specs/script-workspace/spec.md + AGENTS.md §6
import CoreMedia
import Foundation
import SwiftData

/// SwiftData domain model — offline-first, no network, live via `@Query`.
///
/// - `Script` is the source of truth for teleprompter text.
/// - `Take` stores a relative path (`relativeFilePath`) so the file survives
///   container URL changes across app updates (see `Take.documentsDirectory`).
/// - Enums (`LUTPreset`) use raw `String` for `Codable` + `CaseIterable` for pickers,
///   avoiding magic strings per best practices.
@Model
final class Script {
    @Attribute(.unique)
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Take.script)
    var takes: [Take]
    /// Optional — uncategorized scripts live outside any section.
    /// `nullify` on delete keeps scripts alive when their category is removed.
    var category: ScriptCategory?

    init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        takes: [Take] = [],
        category: ScriptCategory? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.takes = takes
        self.category = category
    }

    /// Title for display, defaulting when empty (mirrors row behaviour).
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : title
    }
}

/// A user-created bucket for grouping scripts (e.g. "YouTube", "Pitches").
///
/// An entity rather than a raw string so renaming updates every script at
/// once and the library can offer per-category management without orphaned
/// duplicate spellings.
@Model
final class ScriptCategory {
    @Attribute(.unique)
    var id: UUID
    var name: String
    var symbolName: String
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \Script.category)
    var scripts: [Script]

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "folder",
        createdAt: Date = Date(),
        scripts: [Script] = []
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.createdAt = createdAt
        self.scripts = scripts
    }
}

/// Explicit blade timeline segment — a source-time range that survives export.
///
/// Cut positions alone cannot express "keep both sides, drop the middle", so
/// deletions operate on these ranges (removal IS the compaction) while
/// `Take.bladeCuts` mirrors internal boundaries for the scrubber dividers.
struct BladeSegment: Codable, Equatable {
    /// Source-time start in seconds.
    var start: Double
    /// Length in seconds.
    var duration: Double

    /// Source-time end in seconds.
    var end: Double {
        start + duration
    }
}

/// A recorded take — linked to a script via `scriptID` (not a required relationship,
/// so deletion of a `Script` does not orphan the file path logic).
@Model
final class Take {
    @Attribute(.unique)
    var id: UUID
    var scriptID: UUID
    /// Path relative to the app's Documents directory (survives container URL changes across app updates).
    var relativeFilePath: String
    var createdAt: Date
    var duration: TimeInterval
    /// Trim range as (start seconds, duration seconds) tuple since CMTimeRange is not directly Codable.
    var trimStartSeconds: Double?
    var trimDurationSeconds: Double?
    /// Sorted blade cut positions in seconds (within `duration`), persisted via SwiftData.
    /// `nil` or empty means single segment; cuts are clamped to `(trimStart, trimEnd)` and
    /// deduplicated within 0.1s.
    var bladeCuts: [Double]?
    /// Explicit blade timeline ranges (source timebase). Nil = legacy takes:
    /// derive from `bladeCuts`. Additive Optional → lightweight migration, no
    /// version bump. See `bladeSegments()` + `docs/PERSISTENCE.md` §4.
    var segmentsJSON: String?

    /// Decoded blade ranges (nil when unset or undecodable — falls back to
    /// legacy derivation). Stored as JSON because SwiftData transformable
    /// storage only supports property-list values, not custom `Codable`
    /// struct arrays.
    var segments: [BladeSegment]? {
        get {
            guard let data = segmentsJSON?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([BladeSegment].self, from: data)
        }
        set {
            guard let newValue else {
                segmentsJSON = nil
                return
            }
            segmentsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var lutPreset: String
    var script: Script?
    /// Reaction Studio marker — `true` when the file is a composited cutout
    /// recording (person over background media). Additive with a default so
    /// existing stores migrate lightly; old takes read as non-reaction.
    var isReaction: Bool = false
    /// Photos local identifier of the background clip/image used, if any.
    /// Metadata only (badge/filter) — the composited MP4 is self-contained.
    var backgroundAssetLocalID: String?

    var fileURL: URL {
        get {
            URL(fileURLWithPath: relativeFilePath, relativeTo: Take.documentsDirectory)
        }
        set {
            // Store only the last path component + "Takes/" prefix relative to Documents.
            relativeFilePath = Take.relativePath(for: newValue)
        }
    }

    var trimRange: CMTimeRange? {
        get {
            guard let start = trimStartSeconds, let duration = trimDurationSeconds else { return nil }
            return CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: duration, preferredTimescale: 600)
            )
        }
        set {
            trimStartSeconds = newValue?.start.seconds
            trimDurationSeconds = newValue?.duration.seconds
        }
    }

    init(
        id: UUID = UUID(),
        scriptID: UUID,
        fileURL: URL,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        trimRange: CMTimeRange? = nil,
        lutPreset: String = LUTPreset.natural.rawValue,
        script: Script? = nil,
        bladeCuts: [Double]? = nil,
        segments: [BladeSegment]? = nil,
        isReaction: Bool = false,
        backgroundAssetLocalID: String? = nil
    ) {
        self.id = id
        self.scriptID = scriptID
        relativeFilePath = Take.relativePath(for: fileURL)
        self.createdAt = createdAt
        self.duration = duration
        trimStartSeconds = trimRange?.start.seconds
        trimDurationSeconds = trimRange?.duration.seconds
        self.lutPreset = lutPreset
        self.script = script
        self.bladeCuts = bladeCuts?.sorted()
        if let segments {
            let ordered = segments.sorted { $0.start < $1.start }
            segmentsJSON = (try? JSONEncoder().encode(ordered)).flatMap { String(data: $0, encoding: .utf8) }
        }
        self.isReaction = isReaction
        self.backgroundAssetLocalID = backgroundAssetLocalID
    }

    nonisolated static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    nonisolated static func relativePath(for url: URL) -> String {
        let docsPath = documentsDirectory.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath.hasPrefix(docsPath + "/") {
            return String(urlPath.dropFirst(docsPath.count + 1))
        }
        return "Takes/" + url.lastPathComponent
    }

    // MARK: - Blade helpers

    /// Sorted, deduped cuts clamped to (trimStart, trimEnd) with 0.1s minDistance.
    var normalizedBladeCuts: [Double] {
        guard let cuts = bladeCuts, !cuts.isEmpty else { return [] }
        let start = trimRange?.start.seconds ?? 0
        let end = (trimRange.map { $0.start.seconds + $0.duration.seconds } ?? duration)
        let minDist = 0.1
        let filtered = cuts.filter { $0 > start + minDist && $0 < end - minDist }.sorted()
        var deduped: [Double] = []
        for value in filtered {
            if let last = deduped.last, abs(last - value) < minDist {
                continue
            }
            deduped.append(value)
        }
        return deduped
    }

    /// Effective segments after trim + blade, as CMTimeRanges in source timebase.
    /// Prefers explicit stored ranges; falls back to legacy cut-derivation so
    /// takes predating `segments` behave exactly as before.
    func bladeSegments() -> [CMTimeRange] {
        if let stored = segments, !stored.isEmpty {
            let range = trimRange ?? CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: duration, preferredTimescale: 600)
            )
            let end = range.start.seconds + range.duration.seconds
            let clipped = stored.sorted { $0.start < $1.start }.compactMap { seg -> CMTimeRange? in
                let start = max(seg.start, range.start.seconds)
                let finish = min(seg.end, end)
                guard finish - start > 0.05 else { return nil }
                return CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: finish - start, preferredTimescale: 600)
                )
            }
            return clipped.isEmpty ? [range] : clipped
        }
        return derivedBladeSegments()
    }

    /// Legacy derivation: spans from cut positions (byte-for-byte preserved so
    /// old takes and existing tests behave identically).
    func derivedBladeSegments() -> [CMTimeRange] {
        let cuts = normalizedBladeCuts
        let range = trimRange ?? CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        guard !cuts.isEmpty else { return [range] }
        var spans: [CMTimeRange] = []
        var prev = range.start.seconds
        let end = range.start.seconds + range.duration.seconds
        for cut in cuts {
            if cut <= prev || cut >= end {
                continue
            }
            let seg = CMTimeRange(
                start: CMTime(seconds: prev, preferredTimescale: 600),
                duration: CMTime(seconds: cut - prev, preferredTimescale: 600)
            )
            spans.append(seg)
            prev = cut
        }
        let last = CMTimeRange(
            start: CMTime(seconds: prev, preferredTimescale: 600),
            duration: CMTime(seconds: end - prev, preferredTimescale: 600)
        )
        if last.duration.seconds > 0.05 {
            spans.append(last)
        }
        return spans.isEmpty ? [range] : spans
    }

    /// Duration after blade deletions (sum of surviving segments).
    var bladeEffectiveDuration: TimeInterval {
        bladeSegments().reduce(0) { $0 + $1.duration.seconds }
    }

    /// Prune cuts that fell outside the current trimRange; call on trim change.
    func prunedBladeCuts() -> [Double]? {
        let pruned = normalizedBladeCuts
        return pruned.isEmpty ? nil : pruned
    }

    // MARK: - Explicit range editing (source of truth when `segments` != nil)

    /// Ranges in source timebase: stored, else derived from cuts over the full
    /// duration. Callers mutate the stored list; `bladeSegments()` applies trim.
    func unclippedRanges() -> [BladeSegment] {
        if let stored = segments, !stored.isEmpty {
            return stored.sorted { $0.start < $1.start }
        }
        guard duration > 0.1 else { return [] }
        let cuts = (bladeCuts ?? []).filter { $0 > 0.1 && $0 < duration - 0.1 }.sorted()
        var deduped: [Double] = []
        for value in cuts {
            if let last = deduped.last, abs(last - value) < 0.1 {
                continue
            }
            deduped.append(value)
        }
        var out: [BladeSegment] = []
        var prev = 0.0
        for cut in deduped where cut > prev {
            out.append(BladeSegment(start: prev, duration: cut - prev))
            prev = cut
        }
        if duration - prev > 0.05 {
            out.append(BladeSegment(start: prev, duration: duration - prev))
        }
        return out
    }

    /// Rebuild `bladeCuts` as internal boundaries (nil for ≤1 range).
    /// No-op when no stored ranges exist, preserving legacy cuts verbatim.
    func syncCutsFromSegments() {
        guard let list = segments, list.count > 1 else {
            if segments != nil {
                bladeCuts = nil
            }
            return
        }
        bladeCuts = list.sorted { $0.start < $1.start }.dropFirst().map(\.start)
    }

    /// Split the range containing `time`; returns the right-half index.
    /// No-op (nil) within 0.1s of a boundary — this subsumes the duplicate
    /// rule. Never mutates on the no-op path.
    func split(at time: Double) -> Int? {
        var list = unclippedRanges()
        guard !list.isEmpty else { return nil }
        guard let index = list.firstIndex(where: { $0.start + 0.1 < time && time < $0.end - 0.1 }) else { return nil }
        let seg = list[index]
        list.replaceSubrange(index ... index, with: [
            BladeSegment(start: seg.start, duration: time - seg.start),
            BladeSegment(start: time, duration: seg.end - time),
        ])
        segments = list
        syncCutsFromSegments()
        return index + 1
    }

    /// Delete the range at `index`; removal IS the compaction. Returns false
    /// for the sole survivor or an out-of-bounds index (state untouched).
    /// Index contract: callers clip stored ranges to the visible trim first
    /// (see `clipSegments`), so indices match the displayed spans.
    @discardableResult
    func deleteSegment(at index: Int) -> Bool {
        var list = unclippedRanges()
        guard list.count > 1, list.indices.contains(index) else { return false }
        list.remove(at: index)
        segments = list
        syncCutsFromSegments()
        return true
    }

    /// Ranges clipped to `[start, end)` without mutating (export math).
    /// Sub-0.1s slivers merge into the previous range so indices stay aligned
    /// with the scrubber, which ignores boundaries that close to trim edges.
    func rangesClippedTo(start: Double, end: Double) -> [BladeSegment] {
        Self.clip(unclippedRanges(), start: start, end: end)
    }

    /// Clip stored ranges to `[start, end)`; drop empties (nil when empty).
    /// Returns true when anything changed (caller decides whether to save).
    @discardableResult
    func clipSegments(start: Double, end: Double) -> Bool {
        if segments == nil, (bladeCuts ?? []).isEmpty {
            return false // Un-bladed take: trimming needs no clip work.
        }
        let clipped = Self.clip(unclippedRanges(), start: start, end: end)
        let before = segments
        let beforeCuts = bladeCuts
        if clipped.isEmpty {
            segments = nil
            bladeCuts = nil // fully clipped away: no dividers remain
        } else {
            segments = clipped
            syncCutsFromSegments()
        }
        return segments != before || bladeCuts != beforeCuts
    }

    /// Clip + merge slivers shared by mutating and non-mutating callers.
    private static func clip(_ list: [BladeSegment], start: Double, end: Double) -> [BladeSegment] {
        var merged: [BladeSegment] = []
        for seg in list {
            let clampedStart = max(seg.start, start)
            let clampedEnd = min(seg.end, end)
            guard clampedEnd > clampedStart else { continue }
            let clipped = BladeSegment(start: clampedStart, duration: clampedEnd - clampedStart)
            if clipped.duration < 0.1, let last = merged.last {
                merged[merged.count - 1] = BladeSegment(start: last.start, duration: clipped.end - last.start)
            } else if clipped.duration < 0.1 {
                continue // Leading sliver: trim start covers it.
            } else {
                merged.append(clipped)
            }
        }
        return merged
    }
}

/// GPU 3D LUT presets — backed by `.cube` files in `Resources/`.
///
/// Legacy four ship as raw-binary 64³ dumps; generated grades ship as Adobe
/// text (see `tools/generate_luts.py`) at SIZE 32. `LUTCubeLoader` sniffs both.
///
/// Using an enum with associated `rawValue` prevents magic strings
/// and drives pickers via `CaseIterable`.
enum LUTPreset: String, CaseIterable, Identifiable, Codable {
    case natural
    case warmStudio = "warm_studio"
    case cinematicContrast = "cinematic_contrast"
    case cleanMonochrome = "clean_monochrome"
    case goldenHour = "golden_hour"
    case tealOrange = "teal_orange"
    case fadedFilm = "faded_film"
    case noir
    case vibrantPop = "vibrant_pop"
    case coolMorning = "cool_morning"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .natural: "Natural"
        case .warmStudio: "Warm Studio"
        case .cinematicContrast: "Cinematic Contrast"
        case .cleanMonochrome: "Clean Monochrome"
        case .goldenHour: "Golden Hour"
        case .tealOrange: "Teal & Orange"
        case .fadedFilm: "Faded Film"
        case .noir: "Noir Punch"
        case .vibrantPop: "Vibrant Pop"
        case .coolMorning: "Cool Morning"
        }
    }

    var resourceURL: URL? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "cube") else {
            return nil
        }
        return url
    }

    /// `nil` for natural (identity — skip the filter pass entirely).
    /// Parsed Metal-ready floats via the loader — never raw file bytes.
    var cubeData: Data? {
        LUTCubeLoader.data(for: self)
    }
}
