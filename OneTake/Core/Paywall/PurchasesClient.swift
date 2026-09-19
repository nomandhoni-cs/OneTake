//
//  PurchasesClient.swift
//  OneTake
//
//  Owns: The RevenueCat seam — protocol + live client + value types.
//  Why: Money paths must be unit-testable without StoreKit UI or network, so
//  the service talks to this protocol (mock in tests) and RevenueCat types
//  never leak into views or tests. Trial copy derives from discount objects,
//  never constants, so dashboard/ASC drift shows fallback copy, not lies.
//  See: docs/PRICING.md + openspec/changes/onboarding-terms-paywall/design.md
//
import Foundation
import RevenueCat

/// Billing period unit for trial copy.
enum PaywallPeriodUnit: String, Sendable {
    case day, week, month, year

    func text(value: Int) -> String {
        let unit = value == 1 ? rawValue : rawValue + "s"
        return "\(value) \(unit)"
    }
}

/// Free-trial terms derived from the store discount object.
struct TrialInfo: Sendable, Equatable {
    let periodValue: Int
    let periodUnit: PaywallPeriodUnit
    let priceString: String
}

/// UI-ready package. `rcPackage` carries the live RevenueCat package for
/// purchase; mocks leave it nil. Identity is the package identifier.
struct PaywallPackage: Identifiable, Sendable {
    let id: String
    let title: String
    let priceString: String
    let trial: TrialInfo?
    let kind: Kind
    let rcPackage: Package?

    enum Kind: Sendable {
        case annual, monthly, lifetime, other
    }

    static func == (lhs: PaywallPackage, rhs: PaywallPackage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension PaywallPackage.Kind {
    /// Maps an offering's package identifier (its dashboard lookup key) to a
    /// kind, accepting both RevenueCat's reserved `$rc_*` keys and the plain
    /// names this project's offering uses. `nil` when unrecognised, so the
    /// caller can fall back to `packageType`.
    static func fromIdentifier(_ identifier: String) -> PaywallPackage.Kind? {
        switch identifier.lowercased() {
        case "annual", "$rc_annual", "yearly": .annual
        case "monthly", "$rc_monthly": .monthly
        case "lifetime", "$rc_lifetime": .lifetime
        default: nil
        }
    }
}

extension PaywallPackage: Hashable {}

/// Trial line copy — pure, unit-tested ("7 days free, then $12.99").
enum PaywallCopy {
    static func trialLine(for trial: TrialInfo?) -> String? {
        guard let trial else { return nil }
        return String(localized: "\(trial.periodUnit.text(value: trial.periodValue)) free, then \(trial.priceString)")
    }
}

/// Purchase outcome. Cancellation is data, not an error — stays silent in UI.
enum PurchaseOutcome: Sendable {
    case purchased
    case cancelled
}

/// RevenueCat seam: live in production, mocked in tests.
protocol PurchasesClient: Sendable {
    func loadPackages() async throws -> [PaywallPackage]
    func purchase(_ package: PaywallPackage) async throws -> PurchaseOutcome
    func restore() async throws -> Bool
    func currentProStatus() async throws -> Bool
    func proStatusUpdates() -> AsyncStream<Bool>
}

/// Live RevenueCat implementation.
struct RevenueCatClient: PurchasesClient {
    /// Explicitly nonisolated: the struct holds no state, so the default
    /// value in `ProEntitlementService.init` (evaluated in a nonisolated
    /// context) must not hop to the main actor to build it.
    nonisolated init() {} // swiftlint:disable:this unneeded_synthesized_initializer

    func loadPackages() async throws -> [PaywallPackage] {
        guard Purchases.isConfigured else { throw PaywallError.notConfigured }
        // The dashboard's current offering is the contract — no ID matching here.
        guard let offering = try await Purchases.shared.offerings().current
        else { throw PaywallError.noOffering }
        // RevenueCat drops packages whose StoreKit product did not resolve, so an
        // offering with zero available packages means App Store Connect never
        // returned the products (agreement/metadata), not a network fault.
        let packages = offering.availablePackages
        guard !packages.isEmpty else { throw PaywallError.productsUnavailable }
        return packages.map(Self.map(_:))
    }

    func purchase(_ package: PaywallPackage) async throws -> PurchaseOutcome {
        guard let rcPackage = package.rcPackage else { throw PaywallError.notConfigured }
        let result = try await Purchases.shared.purchase(package: rcPackage)
        if result.userCancelled {
            return .cancelled
        }
        return .purchased
    }

    func restore() async throws -> Bool {
        _ = try await Purchases.shared.restorePurchases()
        return try await currentProStatus()
    }

    func currentProStatus() async throws -> Bool {
        guard Purchases.isConfigured else { return false }
        let info = try await Purchases.shared.customerInfo()
        return info.entitlements[StoreIDs.proEntitlement]?.isActive == true
    }

    func proStatusUpdates() -> AsyncStream<Bool> {
        // Never touch `Purchases.shared` unconfigured — it traps. Pre-key
        // builds (and tests) get a stream that simply ends.
        guard Purchases.isConfigured else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            let task = Task {
                for await info in Purchases.shared.customerInfoStream {
                    continuation.yield(info.entitlements[StoreIDs.proEntitlement]?.isActive == true)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Mapping

    private static func map(_ package: Package) -> PaywallPackage {
        let product = package.storeProduct
        return PaywallPackage(
            id: package.identifier,
            title: product.localizedTitle,
            priceString: product.localizedPriceString,
            trial: trialInfo(for: product),
            kind: kind(for: package),
            rcPackage: package
        )
    }

    /// Free-trial terms from the store discount object — nil without a trial.
    private static func trialInfo(for product: StoreProduct) -> TrialInfo? {
        guard let discount = product.introductoryDiscount,
              discount.paymentMode == .freeTrial
        else { return nil }
        return TrialInfo(
            periodValue: discount.subscriptionPeriod.value,
            periodUnit: PaywallPeriodUnit(discount.subscriptionPeriod.unit),
            priceString: product.localizedPriceString
        )
    }

    private static func kind(for package: Package) -> PaywallPackage.Kind {
        // Identifier first. RevenueCat reports `packageType == .custom` whenever a
        // package's store duration doesn't match one of its canned durations, and
        // logs "has a custom duration … reference this package by its identifier".
        // Our offering hits exactly that, so trusting `packageType` alone mapped
        // every subscription to `.other` — which dropped the trial copy and made
        // the wall pre-select Lifetime instead of Annual.
        if let known = PaywallPackage.Kind.fromIdentifier(package.identifier) {
            return known
        }
        return switch package.packageType {
        case .annual: .annual
        case .monthly: .monthly
        case .lifetime: .lifetime
        default: .other
        }
    }
}

private extension PaywallPeriodUnit {
    init(_ unit: SubscriptionPeriod.Unit) {
        switch unit {
        case .day: self = .day
        case .week: self = .week
        case .month: self = .month
        case .year: self = .year
        @unknown default: self = .month
        }
    }
}

/// Human paywall errors (§11.3 — never raw SDK text in UI).
enum PaywallError: LocalizedError, Equatable {
    case notConfigured
    case noOffering
    case productsUnavailable
    case network
    case storeUnavailable
    case generic

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Purchases aren't set up yet. Please update the app and try again."
        case .noOffering:
            "Plans couldn't be loaded. Check your connection and try again."
        case .productsUnavailable:
            "Plans aren't available from the App Store on this device yet. Please try again later."
        case .network:
            "No connection. Check your connection and try again."
        case .storeUnavailable:
            "The App Store is unavailable right now. Please try again shortly."
        case .generic:
            "Something went wrong. Please try again."
        }
    }

    /// Maps RevenueCat/SK/URL errors to the human set above.
    static func map(_ error: Error) -> PaywallError {
        if let code = error as? ErrorCode {
            switch code {
            case .networkError: .network
            case .storeProblemError, .productNotAvailableForPurchaseError: .storeUnavailable
            default: .generic
            }
        } else if (error as NSError).domain == NSURLErrorDomain {
            .network
        } else {
            .generic
        }
    }
}
