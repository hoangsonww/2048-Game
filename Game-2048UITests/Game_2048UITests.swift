import XCTest

final class Game_2048UITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testGameOpensReadyToPlayWithAccessibleControls() {
        let app = launch()
        XCTAssertTrue(app.otherElements["GameBoard"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Make space."].exists)
        XCTAssertTrue(app.buttons["New game"].exists)
        XCTAssertTrue(app.buttons["How to play"].exists)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        XCTAssertTrue(element(identifier: "ScoreCard", in: app).exists)
        XCTAssertTrue(element(identifier: "BestCard", in: app).exists)
    }

    func testHelpSheetShowsCompleteRulesAndDismisses() {
        let app = launch()
        app.buttons["How to play"].tap()
        XCTAssertTrue(app.navigationBars["How to play"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Slide"].exists)
        XCTAssertTrue(app.staticTexts["Match"].exists)
        XCTAssertTrue(app.staticTexts["Protect space"].exists)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.navigationBars["How to play"].waitForExistence(timeout: 2))
    }

    func testSwipeEnablesUndoAndUndoRestoresRound() {
        let app = launch(state: "merge")
        let board = app.otherElements["GameBoard"]
        XCTAssertTrue(board.waitForExistence(timeout: 15))
        board.swipeLeft()
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        assertScore(36, in: app)
        app.buttons["Undo"].tap()
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        assertScore(32, in: app)
    }

    func testNewGameConfirmationSupportsCancelAndReset() {
        let app = launch(state: "merge")
        app.buttons["New game"].tap()
        XCTAssertTrue(app.staticTexts["Start a fresh board?"].waitForExistence(timeout: 5))
        app.buttons["Keep playing"].tap()
        XCTAssertFalse(app.staticTexts["Start a fresh board?"].exists)
        assertScore(32, in: app)
        app.buttons["New game"].tap()
        XCTAssertTrue(app.staticTexts["Start a fresh board?"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "New game").element(boundBy: 1).tap()
        assertScore(0, in: app)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
    }

    func testWinOverlayCanContinuePlaying() {
        let app = launch(state: "won")
        XCTAssertTrue(app.staticTexts["You made 2048"].waitForExistence(timeout: 15))
        app.buttons["Keep playing"].tap()
        XCTAssertFalse(app.staticTexts["You made 2048"].exists)
        XCTAssertTrue(app.otherElements["GameBoard"].exists)
    }

    func testGameOverOverlayCanStartFreshRound() {
        let app = launch(state: "game-over")
        XCTAssertTrue(app.staticTexts["No more moves"].waitForExistence(timeout: 15))
        app.buttons["Try again"].tap()
        XCTAssertFalse(app.staticTexts["No more moves"].exists)
        assertScore(0, in: app)
    }

    func testLaunchPerformance() {
        let app = XCUIApplication()
        measure(metrics: [XCTApplicationLaunchMetric()]) { app.launch() }
    }

    @discardableResult
    private func launch(state: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let state { app.launchEnvironment["GAME2048_UI_TEST_STATE"] = state }
        app.launch()
        return app
    }

    private func assertScore(_ expected: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let card = element(identifier: "ScoreCard", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(card.label.contains(expected.formatted()), "Expected score card to contain \(expected), got \(card.label)", file: file, line: line)
    }

    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
