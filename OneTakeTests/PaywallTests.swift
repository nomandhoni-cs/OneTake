//
//  PaywallTests.swift
//  OneTakeTests
//
//  Owns: Money-path unit tests — service intents over a mock client.
//  Why: Purchases must be deterministic without StoreKit UI, network, or an
//  API key. Each test gets an isolated `UserDefaults` suite so parallel
//  execution never shares the Pro cache. Live RevenueCat is validated by
//  sandbox QA (see tasks §6.3), not here.
//  See: openspec/changes/onboarding-terms-paywall/specs/paywall/spec.md
//
import Foundation
@testable import OneTake
import RevenueCat
import Testing

/// Isolated service per test — unique defaults suite, scripted mock client.
@MainActor
struct PaywallTests {
    private static func service(
        packages: [PaywallPackage] = PreviewPaywallPackages.all,
        pro: Bool = false,
        purchaseResult: PurchaseOutcome = .purchased,
        error: PaywallError? = nil,
        client: MockPurchasesClient? = nil
    ) -> ProEntitlementService {
        let suite = UserDefaults(suiteName: "PaywallTests-\(UUID().uuidString)") ?? .standard
        let mock = client ?? MockPurchasesClient(packages: packages, pro: pro, purchaseResult: purchaseResult, error: error)
        return ProEntitlementService(client: mock, userDefaults: suite)
    }

    @Test func offeringLoadSelectsAnnualByDefault() async {
        let service = Self.service()
        await service.refresh()
        #expect(service.packages.count == 3)
        #expect(service.selectedPackage?.kind == .annual)
        #expect(service.lastError == nil)
    }

    @Test func purchaseUnlocksPro() async {
        let mock = MockPurchasesClient(packages: PreviewPaywallPackages.all)
        let service = Self.service(client: mock)
        await service.refresh()
        #expect(!service.isPro)
        #expect(await service.purchaseSelected())
        #expect(service.isPro)
    }

    @Test func userCancelledStaysSilentNonPro() async {
        let service = Self.service(purchaseResult: .cancelled)
        await service.refresh()
        #expect(await !(service.purchaseSelected()))
        #expect(!service.isPro)
        #expect(service.lastError == nil) // cancellation is data, not an error
    }

    @Test func purchaseErrorSurfacesHumanString() async {
        let mock = MockPurchasesClient(packages: PreviewPaywallPackages.all)
        let service = Self.service(client: mock)
        await service.refresh()
        mock.error = .network // fail the purchase itself, not the load
        #expect(await !(service.purchaseSelected()))
        #expect(!service.isPro)
        #expect(service.lastError == .network)
        #expect(service.lastError?.localizedDescription.contains("connection") == true)
    }

    @Test func restoreRecoversPro() async {
        let service = Self.service(pro: true)
        #expect(await service.restore())
        #expect(service.isPro)
    }

    @Test func cachedProSurvivesFailedRefresh() async {
        // Offline relaunch: cache says Pro, network fails → gates stay open.
        let suite = UserDefaults(suiteName: "PaywallTests-cache-\(UUID().uuidString)") ?? .standard
        suite.set(true, forKey: "isProCached")
        let service = ProEntitlementService(
            client: MockPurchasesClient(packages: [], pro: false, error: .network),
            userDefaults: suite
        )
        #expect(service.isPro) // cache honored at init
        await service.refresh() // network fails…
        #expect(service.isPro) // …but cached Pro stands
    }

    @Test func trialCopyDerivesFromDiscount() {
        let line = PaywallCopy.trialLine(for: TrialInfo(periodValue: 7, periodUnit: .day, priceString: "$12.99/yr"))
        #expect(line == "7 days free, then $12.99/yr")
        #expect(PaywallCopy
            .trialLine(for: TrialInfo(periodValue: 1, periodUnit: .month, priceString: "$1.99/mo")) == "1 month free, then $1.99/mo")
        #expect(PaywallCopy.trialLine(for: nil) == nil) // no offer → no line, no lie
    }

    @Test func errorMapping() {
        #expect(PaywallError.map(ErrorCode.networkError) == .network)
        #expect(PaywallError.map(ErrorCode.storeProblemError) == .storeUnavailable)
        #expect(PaywallError.map(ErrorCode.productNotAvailableForPurchaseError) == .storeUnavailable)
        let urlError = URLError(.notConnectedToInternet)
        #expect(PaywallError.map(urlError) == .network)
        #expect(PaywallError.map(CancellationError()) == .generic)
    }

    @Test func onboardingGateLogic() {
        #expect(OnboardingFlow.needsOnboarding(completedVersion: 0, acceptedLegalVersion: 0))
        #expect(!OnboardingFlow.needsOnboarding(completedVersion: 2, acceptedLegalVersion: 1))
        #expect(OnboardingFlow.needsOnboarding(completedVersion: 2, acceptedLegalVersion: 0)) // legal bump
        #expect(OnboardingFlow.startStep(completedVersion: 0, acceptedLegalVersion: 0) == .welcome)
        #expect(OnboardingFlow.startStep(completedVersion: 2, acceptedLegalVersion: 0) == .terms)
        #expect(!OnboardingFlow.canSkip(.terms))
        #expect(OnboardingFlow.canSkip(.paywall) && OnboardingFlow.canSkip(.permissions))
        #expect(!OnboardingFlow.canSkip(.welcome))
    }
}
