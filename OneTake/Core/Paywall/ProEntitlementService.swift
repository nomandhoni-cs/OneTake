//
//  ProEntitlementService.swift
//  OneTake
//
//  Owns: Pro state — offering packages, purchase, restore, cached isPro.
//  Why: Views never touch the SDK; they read `isPro`/`packages` and call
//  intents. `isPro` caches in `@AppStorage` so gates work offline; the
//  `customerInfoStream` listener + explicit refreshes converge it to server
//  truth. Cancellation is silent data, never an error surface.
//  See: docs/PRICING.md + openspec/changes/onboarding-terms-paywall/design.md
//
import Foundation
import RevenueCat
import SwiftUI

/// Pro entitlement owner. Inject via `.environment()`; previews/tests use the
/// `preview`/`mock` constructors. All state main-actor bound (§13.4).
@Observable
@MainActor
final class ProEntitlementService {
    private let client: PurchasesClient
    private let userDefaults: UserDefaults
    /// Listener handle must die with the service, but `deinit` is nonisolated —
    /// `Task.cancel()` is thread-safe, so unsynchronized storage is sound.
    private nonisolated(unsafe) var listenerTask: Task<Void, Never>?

    /// Offline-safe cache key — the gate source when the network is gone.
    /// Plain `UserDefaults` (not `@AppStorage`): property wrappers collide
    /// with `@Observable` synthesis; `isPro` below is the tracked mirror.
    private static let proCacheKey = "isProCached"

    private(set) var isPro = false
    private(set) var packages: [PaywallPackage] = []
    private(set) var selectedPackageID: String?
    private(set) var isLoadingPackages = false
    private(set) var isPurchasing = false
    private(set) var lastError: PaywallError?

    /// `userDefaults` is injectable so parallel tests never share the cache.
    init(client: PurchasesClient = RevenueCatClient(), userDefaults: UserDefaults = .standard) {
        self.client = client
        self.userDefaults = userDefaults
        isPro = userDefaults.bool(forKey: Self.proCacheKey)
        #if DEBUG
            // Dev-only escape hatch (stripped from release builds): launch with
            // `-pro` to unlock gates before the dashboard/API key exist.
            if CommandLine.arguments.contains("-pro") {
                isPro = true
            }
        #endif
        listenerTask = Task { [weak self] in
            guard let updates = self?.client.proStatusUpdates() else { return }
            for await pro in updates {
                await MainActor.run { self?.apply(pro: pro) }
            }
        }
    }

    deinit {
        listenerTask?.cancel()
    }

    var selectedPackage: PaywallPackage? {
        packages.first { $0.id == selectedPackageID } ?? packages.first
    }

    /// Loads packages + converges `isPro` to server truth. Safe to call often.
    func refresh() async {
        isLoadingPackages = true
        defer { isLoadingPackages = false }
        async let loadedPackages = client.loadPackages()
        async let pro = client.currentProStatus()
        do {
            let (fetched, isProNow) = try await (loadedPackages, pro)
            packages = fetched
            if selectedPackageID == nil {
                // Default to annual (carries the trial) when present.
                selectedPackageID = fetched.first { $0.kind == .annual }?.id ?? fetched.first?.id
            }
            apply(pro: isProNow)
            lastError = nil
        } catch {
            lastError = error as? PaywallError ?? PaywallError.map(error)
        }
    }

    func select(_ package: PaywallPackage) {
        selectedPackageID = package.id
        lastError = nil
    }

    /// Purchases the selected package. Returns true when Pro unlocked.
    @discardableResult
    func purchaseSelected() async -> Bool {
        guard let package = selectedPackage, !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await client.purchase(package) {
            case .cancelled:
                return false // silent — the user changed their mind
            case .purchased:
                await refresh()
                return isPro
            }
        } catch {
            lastError = error as? PaywallError ?? PaywallError.map(error)
            return false
        }
    }

    /// Restores past purchases. Returns true when Pro unlocked.
    @discardableResult
    func restore() async -> Bool {
        do {
            let pro = try await client.restore()
            apply(pro: pro)
            if pro {
                await refresh()
            }
            lastError = nil
            return pro
        } catch {
            lastError = error as? PaywallError ?? PaywallError.map(error)
            return false
        }
    }

    private func apply(pro: Bool) {
        isPro = pro
        userDefaults.set(pro, forKey: Self.proCacheKey)
    }
}

// MARK: - Previews & tests

extension ProEntitlementService {
    /// Synchronous preview/test instance — no SDK, no network.
    static func preview(packages: [PaywallPackage] = [], isPro: Bool = false) -> ProEntitlementService {
        let service = ProEntitlementService(client: MockPurchasesClient(packages: packages, pro: isPro))
        service.packages = packages
        service.selectedPackageID = packages.first { $0.kind == .annual }?.id ?? packages.first?.id
        service.apply(pro: isPro)
        return service
    }

    static var previewLocked: ProEntitlementService {
        preview(packages: PreviewPaywallPackages.all, isPro: false)
    }

    static var previewUnlocked: ProEntitlementService {
        preview(packages: PreviewPaywallPackages.all, isPro: true)
    }
}

/// Fixed preview catalog — plain structs, no SDK (RC `TestStoreProduct`
/// previews are unnecessary behind the `PaywallPackage` seam).
enum PreviewPaywallPackages {
    static let all: [PaywallPackage] = [
        PaywallPackage(
            id: "annual",
            title: "OneTake Pro Annual",
            priceString: "$12.99/yr",
            trial: TrialInfo(periodValue: 7, periodUnit: .day, priceString: "$12.99/yr"),
            kind: .annual,
            rcPackage: nil
        ),
        PaywallPackage(
            id: "monthly",
            title: "OneTake Pro Monthly",
            priceString: "$1.99/mo",
            trial: nil,
            kind: .monthly,
            rcPackage: nil
        ),
        PaywallPackage(
            id: "lifetime",
            title: "OneTake Pro Lifetime",
            priceString: "$39.99",
            trial: nil,
            kind: .lifetime,
            rcPackage: nil
        ),
    ]
}

/// Scriptable mock client for unit tests (and previews). A class so tests can
/// flip behavior mid-flow (e.g. load OK, then fail purchase); each test owns
/// its instance, so the unchecked Sendable is sound under parallel execution.
final class MockPurchasesClient: PurchasesClient, @unchecked Sendable {
    var packages: [PaywallPackage]
    var pro: Bool
    var purchaseResult: PurchaseOutcome
    var error: PaywallError?

    init(
        packages: [PaywallPackage] = [],
        pro: Bool = false,
        purchaseResult: PurchaseOutcome = .purchased,
        error: PaywallError? = nil
    ) {
        self.packages = packages
        self.pro = pro
        self.purchaseResult = purchaseResult
        self.error = error
    }

    func loadPackages() async throws -> [PaywallPackage] {
        if let error {
            throw error
        }
        return packages
    }

    func purchase(_ package: PaywallPackage) async throws -> PurchaseOutcome {
        if let error {
            throw error
        }
        if purchaseResult == .purchased {
            pro = true // server now entitles Pro — later refreshes converge
        }
        return purchaseResult
    }

    func restore() async throws -> Bool {
        if let error {
            throw error
        }
        return pro
    }

    func currentProStatus() async throws -> Bool {
        if let error {
            throw error
        }
        return pro
    }

    func proStatusUpdates() -> AsyncStream<Bool> {
        AsyncStream { $0.finish() } // tests drive state via refresh/purchase/restore
    }
}
