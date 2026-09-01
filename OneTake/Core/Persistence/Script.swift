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
    var lutPreset: String
    var script: Script?

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
        bladeCuts: [Double]? = nil
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
    func bladeSegments() -> [CMTimeRange] {
        let cuts = normalizedBladeCuts
        let range = trimRange ?? CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        guard !cuts.isEmpty else { return [range] }
        var segments: [CMTimeRange] = []
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
            segments.append(seg)
            prev = cut
        }
        let last = CMTimeRange(
            start: CMTime(seconds: prev, preferredTimescale: 600),
            duration: CMTime(seconds: end - prev, preferredTimescale: 600)
        )
        if last.duration.seconds > 0.05 {
            segments.append(last)
        }
        return segments.isEmpty ? [range] : segments
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
}

/// GPU 3D LUT presets — backed by 64³ `.cube` files in `Resources/`.
///
/// Using an enum with associated `rawValue` prevents magic strings
/// and drives pickers via `CaseIterable`.
enum LUTPreset: String, CaseIterable, Identifiable, Codable {
    case natural
    case warmStudio = "warm_studio"
    case cinematicContrast = "cinematic_contrast"
    case cleanMonochrome = "clean_monochrome"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .natural: "Natural"
        case .warmStudio: "Warm Studio"
        case .cinematicContrast: "Cinematic Contrast"
        case .cleanMonochrome: "Clean Monochrome"
        }
    }

    var resourceURL: URL? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "cube") else {
            return nil
        }
        return url
    }

    /// `nil` for natural (identity — skip the filter pass entirely).
    var cubeData: Data? {
        guard self != .natural, let url = resourceURL else { return nil }
        return try? Data(contentsOf: url)
    }
}
