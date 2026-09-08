//
//  FirstLaunchUITests.swift
//  OneTakeUITests
//

import XCTest

/// Versioned onboarding (guidelines §15: decision surfaces, not a tutorial).
/// Fresh installs walk decisions with no system prompts; relaunches land
/// straight in tabs. Never taps record (would raise a system camera prompt).
final class FirstLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFreshInstallWalksDecisionsToTabs() {
        let app = XCUIApplication()
        app.launch()
        guard app.buttons["Continue"].waitForExistence(timeout: 5) else {
            // Returning user (shared container) — tabs are showing.
            XCTAssertTrue(app.tabBars.buttons["Studio"].exists)
            return
        }
        // Welcome → Terms (blocking) → Trial offer (skippable) → Explainer.
        app.buttons["Continue"].tap()
        let agree = app.buttons["Agree to Terms and Privacy Policy"]
        XCTAssertTrue(agree.waitForExistence(timeout: 5))
        agree.tap()
        XCTAssertTrue(app.navigationBars["OneTake Pro"].waitForExistence(timeout: 5))
        app.buttons["Skip subscription for now"].tap()
        let done = app.buttons["Finish onboarding"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.tabBars.buttons["Studio"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSecondLaunchGoesStraightToTabs() {
        let app = XCUIApplication()
        app.launch()
        ensurePastOnboarding(app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Studio"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue"].exists)
    }

    @MainActor
    func testReplayTourFromProfile() {
        let app = XCUIApplication()
        app.launch()
        ensurePastOnboarding(app)
        app.tabBars.buttons["Profile"].tap()
        // About section sits below the fold — scroll to materialize rows.
        app.swipeUp()
        let replay = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'replay welcome tour'")).firstMatch
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        replay.tap()
        // Replayed tour always starts at welcome, then walks and dismisses.
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        app.buttons["Agree to Terms and Privacy Policy"].tap()
        app.buttons["Skip subscription for now"].tap()
        app.buttons["Finish onboarding"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testScriptsTabShowsTeachingEmptyState() {
        let app = XCUIApplication()
        app.launch()
        ensurePastOnboarding(app)
        app.tabBars.buttons["Scripts"].tap()
        // Either the empty state (fresh install) or the library (seeded data) —
        // both are usable content, never a blocking gate.
        let emptyState = app.staticTexts["No Scripts Yet"]
        let library = app.navigationBars["OneTake"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5) || library.exists)
    }
}
