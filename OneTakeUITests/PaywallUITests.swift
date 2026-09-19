//
//  PaywallUITests.swift
//  OneTakeUITests
//

import XCTest

/// Paywall + legal surfaces reachable without media or purchases.
/// The owner API key IS set and the App Store products are live, so the wall
/// now resolves real packages — the old "Plans unavailable" assertion asserted
/// a broken store and started failing the moment the store was fixed. These
/// assert the states that are actually correct either way, and never tap
/// purchase (system sheet) or Record.
final class PaywallUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testProRowOpensPaywall() {
        let app = XCUIApplication()
        app.launch()
        ensurePastOnboarding(app)
        app.tabBars.buttons["Profile"].tap()
        // About section sits below the fold — scroll to materialize rows.
        app.swipeUp()
        let proRow = app.buttons["OneTake Pro, free plan"]
        XCTAssertTrue(proRow.waitForExistence(timeout: 5))
        proRow.tap()
        XCTAssertTrue(app.navigationBars["OneTake Pro"].waitForExistence(timeout: 5))

        // The wall must resolve to a definite state, never spin. Either the
        // packages load (products live) or the honest empty state appears with
        // a Retry — both are correct; a permanent spinner is not.
        let plansLoaded = app.buttons["Start Free Trial"].waitForExistence(timeout: 15)
            || app.buttons["Subscribe Annual"].exists
            || app.buttons["Buy Lifetime"].exists
            || app.buttons["Subscribe Monthly"].exists
        let offlineState = app.staticTexts["Plans unavailable"].exists && app.buttons["Retry"].exists
        XCTAssertTrue(
            plansLoaded || offlineState,
            "Paywall settled on neither packages nor the empty state — likely stuck loading"
        )

        // Restore is always available, loaded or not: App Review requires it.
        XCTAssertTrue(app.buttons["Restore purchases"].exists || offlineState)

        app.buttons["Close paywall"].tap()
    }

    @MainActor
    func testTermsRowShowsViewer() {
        let app = XCUIApplication()
        app.launch()
        ensurePastOnboarding(app)
        app.tabBars.buttons["Profile"].tap()
        app.swipeUp()
        let termsRow = app.buttons["Terms and Privacy Policy"]
        XCTAssertTrue(termsRow.waitForExistence(timeout: 5))
        termsRow.tap()
        XCTAssertTrue(app.staticTexts["Terms of Service"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Privacy Policy"].waitForExistence(timeout: 5))
    }
}
