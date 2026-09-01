//
//  StudioSettings.swift
//  OneTake
//

import SwiftUI

/// Camera defaults persisted via `@AppStorage` (UserDefaults).
enum Resolution: String, CaseIterable, Identifiable {
    case hd1080p = "1080p"
    case uhd4K = "4K"

    var id: String {
        rawValue
    }

    nonisolated var displayName: String {
        switch self {
        case .hd1080p: "1080p FHD"
        case .uhd4K: "4K UHD"
        }
    }

    nonisolated var pixelSize: (width: Int32, height: Int32) {
        switch self {
        case .hd1080p: (1920, 1080)
        case .uhd4K: (3840, 2160)
        }
    }
}

enum FrameRate: Int, CaseIterable, Identifiable {
    case film = 24
    case standard = 30
    case smooth = 60

    var id: Int {
        rawValue
    }

    nonisolated var displayName: String {
        switch self {
        case .film: "24 fps · Film"
        case .standard: "30 fps · Standard"
        case .smooth: "60 fps · Smooth"
        }
    }
}

enum AspectRatio: String, CaseIterable, Identifiable {
    case vertical = "9:16"
    case wide = "16:9"
    case square = "1:1"

    var id: String {
        rawValue
    }

    nonisolated var displayName: String {
        switch self {
        case .vertical: "9:16 Reels/Shorts"
        case .wide: "16:9 YouTube"
        case .square: "1:1 Square"
        }
    }
}

// MARK: - Studio settings defaults (single source of truth for @AppStorage keys)

enum StudioSettings {
    static let defaultResolution = Resolution.hd1080p
    static let defaultFrameRate = FrameRate.standard
    static let defaultMirror = true
    static let defaultCountdown = 3
    static let defaultAspect = AspectRatio.wide
    static let defaultLUT = LUTPreset.natural
}
