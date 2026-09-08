//
//  PaywallUITests.swift
//  OneTakeUITests
//

import XCTest

/// Paywall + legal surfaces reachable without media, purchases, or keys.
/// Without the owner API key the wall deterministically shows its offline
/// state — asserted here. Never taps purchase (system sheet) or Record.
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
        // No API key in test builds → honest offline state, never a spinner loop.
        XCTAssertTrue(app.staticTexts["Plans unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Retry"].exists)
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
