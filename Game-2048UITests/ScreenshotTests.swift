import XCTest

/// Captures the canonical iOS screenshots.
///
/// This is a test only because XCUITest is the only way to drive a simulator:
/// there is no tap CLI. It asserts nothing about behaviour — the suites in
/// `Game_2048UITests` do that — and it is excluded from `make test-ios` by
/// name, so a capture run never gates a merge and a merge never waits on a
/// capture.
///
/// Each frame is kept as a named XCTest attachment. The capture script exports
/// those attachments from the result bundle after the run; unlike an ad-hoc
/// host path, that is a supported boundary between the simulator and macOS.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureCanonicalScreens() {
        // A played round, so the board has colour in it and the handover
        // warning has something to warn about.
        let app = XCUIApplication()
        app.launchEnvironment["GAME2048_UI_TEST_STATE"] = "merge"
        app.launch()

        let board = app.otherElements["GameBoard"]
        XCTAssertTrue(board.waitForExistence(timeout: 30))
        // The invite toast is on screen for its first few seconds.
        save(app, as: "ios-guest")

        board.swipeLeft()
        board.swipeUp()
        Thread.sleep(forTimeInterval: 6)
        save(app, as: "ios-main")

        app.buttons["accountButton"].tap()
        // A leftover simulator session opens Account instead of Sign in.
        if app.buttons["signOutButton"].waitForExistence(timeout: 2) {
            app.buttons["signOutButton"].tap()
            XCTAssertTrue(board.waitForExistence(timeout: 5))
            // Signing out restores the parked guest round; swipe again so the
            // handover warning still has progress to warn about.
            board.swipeLeft()
            board.swipeUp()
            app.buttons["accountButton"].tap()
        }
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 10))
        save(app, as: "ios-signin")

        app.buttons["authSwitch"].tap()
        XCTAssertTrue(app.staticTexts["Create your account"].waitForExistence(timeout: 10))
        save(app, as: "ios-signup")

        app.buttons["authSubmit"].tap()
        XCTAssertTrue(app.alerts["Set this round aside?"].waitForExistence(timeout: 10))
        save(app, as: "ios-handover")
        app.alerts.buttons["Keep playing"].tap()

        app.buttons["authSwitch"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 10))

        app.buttons["authForgot"].tap()
        XCTAssertTrue(app.staticTexts["Reset your password"].waitForExistence(timeout: 10))
        save(app, as: "ios-reset")
        app.buttons["resetDismiss"].tap()

        app.buttons["leaderboardButton"].tap()
        XCTAssertTrue(app.staticTexts["Leaderboard"].waitForExistence(timeout: 10))
        // The board is fetched over the network; give it a moment to answer
        // or to say it could not.
        Thread.sleep(forTimeInterval: 6)
        save(app, as: "ios-leaderboard")
    }

    private func save(_ app: XCUIApplication, as name: String) {
        _ = app.wait(for: .runningForeground, timeout: 5)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Focused maintainer notes (documentation only)
//
// Canonical screenshot maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Capture only deterministic named states used by repository documentation.
//
// 02. Wait for each state to settle before taking the attachment.
//
// 03. Keep filenames stable because promotion scripts and documentation reference them.
//
// 04. Exercise both gameplay and cloud-account surfaces represented in product docs.
//
// 05. Do not hide accessibility or layout defects merely to obtain a clean image.
//
// 06. Use the repository screenshot workflow for promotion and keep ad-hoc output under output.
//
// 07. Review compact and large layouts whenever the affected view changes.
//
// 08. Avoid changing canonical images for comment-only or nonvisual work.
//
// Symbol and scenario index
//
// 01. `final class ScreenshotTests: XCTestCase`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `func testCaptureCanonicalScreens()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 03. `private func save(_ app: XCUIApplication, as name: String)`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
