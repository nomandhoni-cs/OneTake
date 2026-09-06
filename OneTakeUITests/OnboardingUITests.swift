//
//  OnboardingUITests.swift
//  OneTakeUITests
//

import XCTest

/// First-launch onboarding: splash → pages → permission rationale → tabs.
/// Never taps "Enable Camera & Mic" (would raise a system prompt).
final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSkipGoesStraightToTabs() {
        let app = XCUIApplication()
        app.launch()
        guard app.buttons["Skip onboarding"].waitForExistence(timeout: 5) else {
            // Flag already set from an earlier test — tabs are showing.
            XCTAssertTrue(app.tabBars.buttons["Studio"].exists)
            return
        }
        app.buttons["Skip onboarding"].tap()
        XCTAssertTrue(app.tabBars.buttons["Studio"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFullFlowReachesTabs() {
        let app = XCUIApplication()
        app.launch()
        guard app.staticTexts["OneTake"].waitForExistence(timeout: 5) else {
            // Already onboarded — nothing to walk through.
            XCTAssertTrue(app.tabBars.buttons["Studio"].exists)
            return
        }
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Write your script"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Read, react, record"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Enable camera & mic"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Enable Camera and Mic"].exists)
        XCTAssertTrue(app.buttons["Get Started"].exists)
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.tabBars.buttons["Studio"].waitForExistence(timeout: 5))
    }
}
