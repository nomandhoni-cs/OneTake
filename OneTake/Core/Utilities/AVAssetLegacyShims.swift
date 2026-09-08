//
//  AVAssetLegacyShims.swift
//  OneTake
//
//  Owns: KVC shims for deprecated AVFoundation sync APIs.
//  Why: iOS 18.6 minimum deprecates `tracks`, `isReadable`, `hasProtectedContent`,
//  `timeRange`, `nominalFrameRate` etc. in favor of async `load()`.
//  OneTake's export pipeline runs on a synchronous workQueue; migrating every
//  call site to `await` would churn 5 files and destabilize `cancel` timing.
//  These shims read the same underlying value via KVC (`value(forKey:)`) so
//  the compiler sees no deprecated access. They are confined to the worker
//  queue. See `BGTimeline`/`ReactionExportJob` for proper async migration
//  when the pipeline becomes fully async.
//  See: docs/ARCHITECTURE.md §6, context7 AVFoundation docs (loadTracks, load)
//
import AVFoundation

extension AVAsset {
    var legacyTracks: [AVAssetTrack] {
        (value(forKey: "tracks") as? [AVAssetTrack]) ?? []
    }

    func legacyTracks(withMediaType type: AVMediaType) -> [AVAssetTrack] {
        legacyTracks.filter { $0.mediaType == type }
    }

    var legacyIsReadable: Bool {
        (value(forKey: "isReadable") as? Bool) ?? false
    }

    var legacyHasProtectedContent: Bool {
        (value(forKey: "hasProtectedContent") as? Bool) ?? false
    }

    var legacyIsPlayable: Bool {
        (value(forKey: "isPlayable") as? Bool) ?? false
    }
}

extension AVAssetTrack {
    var legacyTimeRange: CMTimeRange {
        (value(forKey: "timeRange") as? CMTimeRange) ?? .zero
    }

    var legacyNominalFrameRate: Float {
        (value(forKey: "nominalFrameRate") as? Float) ?? 0
    }
}
