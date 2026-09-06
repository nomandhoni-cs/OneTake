//
//  ReactionStudioUITests.swift
//  OneTakeUITests
//

import XCTest

final class ReactionStudioUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReactionModeOpensFromPicker() {
        let app = XCUIApplication()
        app.launch()
        ensurePastOnboarding(app)
        app.tabBars.buttons["Studio"].tap()

        let teleprompterCard = app.buttons["Teleprompter"]
        let reactionCard = app.buttons["Reaction"]
        XCTAssertTrue(teleprompterCard.waitForExistence(timeout: 5))
        XCTAssertTrue(reactionCard.exists)

        reactionCard.tap()

        // No background yet in a fresh simulator → empty state with BG action.
        XCTAssertTrue(app.staticTexts["Pick a background to react to"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pick background media"].exists)

        // Top chrome must sit below the status bar (time/network/battery),
        // not under it. Threshold assumes a Dynamic Island device (the suite
        // runs on iPhone 17 Pro, island bottom edge ≈ 59pt).
        let closeButton = app.buttons["Close reaction studio"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(closeButton.frame.minY, 50, "Close button overlaps the status bar")
        XCTAssertGreaterThan(app.buttons["Reaction settings"].frame.minY, 50, "Settings button overlaps the status bar")

        // Settings are ranked Cutout → Audio → Notes → Camera, with a spatial
        // grid for the presenter position.
        app.buttons["Reaction settings"].tap()
        XCTAssertTrue(app.staticTexts["Cutout"].waitForExistence(timeout: 5), "Cutout section missing")
        // Lower sections are virtualized until scrolled into view — drag the
        // list content upward to materialize them.
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        lower.press(forDuration: 0.1, thenDragTo: upper)
        XCTAssertTrue(app.staticTexts["Audio"].waitForExistence(timeout: 5), "Audio section missing")
        XCTAssertTrue(app.buttons["Move presenter bottom right"].waitForExistence(timeout: 5), "Position grid cell missing")
        app.buttons["Done"].tap()

        closeButton.tap()
        XCTAssertTrue(app.buttons["Reaction"].waitForExistence(timeout: 5))
    }
}
