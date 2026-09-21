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
        XCTAssertTrue(app.navigationBars["Create your account"].waitForExistence(timeout: 10))
        save(app, as: "ios-signup")

        app.buttons["authSubmit"].tap()
        if app.alerts["Set this round aside?"].waitForExistence(timeout: 10) {
            save(app, as: "ios-handover")
            app.alerts.buttons["Keep playing"].tap()
        }

        app.buttons["authSwitch"].tap()
        XCTAssertTrue(app.navigationBars["Welcome back"].waitForExistence(timeout: 10))
        save(app, as: "ios-signin")

        app.buttons["authForgot"].tap()
        XCTAssertTrue(app.navigationBars["Reset your password"].waitForExistence(timeout: 10))
        save(app, as: "ios-reset")
        app.buttons["resetDismiss"].tap()

        app.buttons["leaderboardButton"].tap()
        XCTAssertTrue(app.navigationBars["Leaderboard"].waitForExistence(timeout: 10))
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
