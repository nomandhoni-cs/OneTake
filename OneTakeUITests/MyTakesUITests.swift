//
//  MyTakesUITests.swift
//  OneTakeUITests
//

import XCTest

/// My Takes first-frame contract (guidelines §10.3, §5.2): teaching empty
/// state, search-empty state, and Record entry — all reachable without media.
/// Never taps Record (would raise a system camera prompt) and never needs
/// seeded takes, so these stay green on a fresh simulator.
final class MyTakesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTakesFirstFrame() {
        let app = XCUIApplication()
        app.launch()
        ensurePastOnboarding(app)
        app.tabBars.buttons["My Takes"].tap()
        XCTAssertTrue(app.navigationBars["My Takes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record"].exists)
        XCTAssertTrue(app.searchFields["Search script title"].exists)
    }

    @MainActor
    func testSearchEmptyState() {
        let app = XCUIApplication()
        app.launch()
        ensurePastOnboarding(app)
        app.tabBars.buttons["My Takes"].tap()
        let search = app.searchFields["Search script title"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("zzz-no-such-take")
        let noResults = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'No Results'"))
        XCTAssertTrue(noResults.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordToolbarButtonExists() {
        let app = XCUIApplication()
        app.launch()
        ensurePastOnboarding(app)
        app.tabBars.buttons["My Takes"].tap()
        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 5))
    }
}
