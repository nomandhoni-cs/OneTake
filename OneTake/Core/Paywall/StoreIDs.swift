//
//  StoreIDs.swift
//  OneTake
//
//  Owns: RevenueCat wiring constants — public API key, entitlement, products.
//  Why: One file to finish before App Store submission; `#warning` keeps the
//  two owner steps (dashboard objects + key) visible at build time.
//  See: docs/PRICING.md + openspec/changes/onboarding-terms-paywall/design.md
//
import Foundation

#warning(
    "Owner setup: create the RC app + entitlement + products, then paste the PUBLIC api key below. App stays locked until set."
)

enum StoreIDs {
    /// RevenueCat PUBLIC api key (`appl_…`). Safe to ship in-client by design.
    static let revenueCatAPIKey = ""

    /// Entitlement identifier — must match the RevenueCat dashboard exactly.
    static let proEntitlement = "pro"

    /// Store product IDs — must match App Store Connect (mirrored in RC).
    static let annual = "com.nomandhoni.onetake.annual" // $12.99/yr, 7-day trial
    static let monthly = "com.nomandhoni.onetake.monthly" // $1.99/mo, no trial
    static let lifetime = "com.nomandhoni.onetake.lifetime" // $39.99 one-time

    static var isConfigured: Bool {
        !revenueCatAPIKey.isEmpty
    }
}
