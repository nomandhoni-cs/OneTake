//
//  FlowHelpers.swift
//  OneTakeUITests
//

import XCTest

/// Walks the versioned onboarding decision flow when present (fresh
/// simulator) and no-ops for returning users. The flow fires no system
/// prompts, so every step is tappable: Welcome → Terms (agree) → Trial
/// offer (skip) → Permissions explainer → tabs.
@MainActor
func ensurePastOnboarding(_ app: XCUIApplication) {
    guard app.buttons["Continue"].waitForExistence(timeout: 5) else {
        return // already onboarded — tabs are showing
    }
    app.buttons["Continue"].tap()
    let agree = app.buttons["Agree to Terms and Privacy Policy"]
    if agree.waitForExistence(timeout: 5) {
        agree.tap()
    }
    // Trial offer wall (offline state without the owner key) — skip it.
    let notNow = app.buttons["Skip subscription for now"]
    if notNow.waitForExistence(timeout: 5) {
        notNow.tap()
    }
    let done = app.buttons["Finish onboarding"]
    if done.waitForExistence(timeout: 5) {
        done.tap()
    }
    XCTAssertTrue(app.tabBars.buttons["Studio"].waitForExistence(timeout: 5))
}
