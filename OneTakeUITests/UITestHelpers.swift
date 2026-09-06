//
//  UITestHelpers.swift
//  OneTakeUITests
//

import XCTest

/// First launch shows onboarding instead of tabs — skip it when present so
/// studio tests always start from the tab shell. Safe to call when the flag
/// is already set (no-op).
@MainActor
func dismissOnboardingIfNeeded(_ app: XCUIApplication) {
    let skip = app.buttons["Skip onboarding"]
    if skip.waitForExistence(timeout: 3) {
        skip.tap()
    }
}
