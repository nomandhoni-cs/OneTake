//
//  AppTheme.swift
//  OneTake
//
//  Brand palette — single source of truth for app-wide colors.
//
//  Both brand colors are lifted from the app icon (`Resources/logo.icon`):
//    • #195636 deep green → `AccentColor` in the asset catalog (app accent)
//    • #FCCD03 yellow     → `BrandSecondary` in the asset catalog
//
//  The asset catalog stays authoritative so the same colors also drive UIKit
//  tinting, widgets and Live Activities. These tokens give SwiftUI code a
//  typed, discoverable way to reach them.
//

//  See: docs/ARCHITECTURE.md §5 (Theme) + AGENTS.md §3
import SwiftUI

extension Color {
    /// Deep brand green — #195636.
    ///
    /// Mirrors `AccentColor` in the asset catalog, which Xcode wires up as the
    /// app-wide accent through `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`.
    static let appAccent = Color("AccentColor")

    /// Brand yellow — #FCCD03, the highlight from the app icon.
    ///
    /// Mirrors `BrandSecondary` in the asset catalog. Best used for emphasis
    /// against dark surfaces (REC indicators, active recording state) rather
    /// than as a background, where it needs dark text for contrast.
    ///
    /// The set is named `BrandSecondary`, not `SecondaryColor`, because Xcode's
    /// generated asset symbol for the latter collides with SwiftUI's
    /// `Color.secondary` and warns on every build.
    static let appSecondary = Color("BrandSecondary")
}
