//
//  Game_2048UITestsLaunchTests.swift
//  Game-2048UITests
//
//  Created by Dav Nguyen on 3/19/24.
//

import XCTest

final class Game_2048UITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["GAME2048_UI_TESTING"] = "1"
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Focused maintainer notes (documentation only)
//
// Launch test maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Treat launch as a clean process boundary.
//
// 02. Capture attachments only after the first stable interactive frame.
//
// 03. Keep launch arguments explicit when a deterministic profile is required.
//
// 04. Avoid sharing application instances with other UI tests.
//
// 05. Retain failure artifacts long enough to diagnose CI-only startup failures.
//
// 06. Keep this target lightweight so launch coverage remains fast and dependable.
//
// Symbol and scenario index
//
// 01. `final class Game_2048UITestsLaunchTests: XCTestCase`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `func testLaunch() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
