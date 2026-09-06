//
//  TeleprompterStudioUITests.swift
//  OneTakeUITests
//

import XCTest

/// Parity with the reaction studio: the teleprompter opens fullscreen with a
/// native toolbar (close + script + settings) below the status bar.
final class TeleprompterStudioUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTeleprompterModeOpensFullscreen() {
        let app = XCUIApplication()
        app.launch()
        ensurePastOnboarding(app)
        app.tabBars.buttons["Studio"].tap()

        let teleprompterCard = app.buttons["Teleprompter"]
        XCTAssertTrue(teleprompterCard.waitForExistence(timeout: 5))
        teleprompterCard.tap()

        // Native toolbar chrome, all below the status bar (Dynamic Island
        // bottom edge ≈ 59pt on the iPhone 17 Pro test device).
        let closeButton = app.buttons["Close studio"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(closeButton.frame.minY, 50, "Close button overlaps the status bar")
        XCTAssertGreaterThan(app.buttons["Camera settings"].frame.minY, 50, "Settings button overlaps the status bar")
        XCTAssertTrue(app.buttons["Select script"].exists)

        closeButton.tap()
        XCTAssertTrue(app.buttons["Teleprompter"].waitForExistence(timeout: 5))
    }
}
