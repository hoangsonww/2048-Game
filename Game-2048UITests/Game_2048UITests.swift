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

    /// A vertical board swipe must reach the game rather than the surrounding
    /// container.
    ///
    /// The layout used to ask for ~887pt inside an 874pt viewport. That 13pt
    /// overflow selected a scrolling layout, and a ScrollView's pan is a UIKit
    /// recogniser that outranks the board's SwiftUI DragGesture, so every
    /// vertical swipe scrolled the page and never moved a tile. Guard all three
    /// facts: no scrolling container, nothing moves, and the swipe registers.
    func testVerticalBoardSwipeReachesTheBoardAndDoesNotMoveTheScreen() {
        let app = launch(state: "merge")
        let board = app.otherElements["GameBoard"]
        XCTAssertTrue(board.waitForExistence(timeout: 15))

        XCTAssertFalse(app.scrollViews.firstMatch.exists,
                       "the board must not sit inside a scrolling container")

        // Anchor on chrome outside the board: if the container scrolls, this
        // moves even when the board's own frame does not.
        let title = app.staticTexts["Make space."]
        XCTAssertTrue(title.exists)
        let titleBefore = title.frame
        let boardBefore = board.frame

        // The fixture is [2, 2, 0, 0] on the top row, so up is legitimately an
        // ineffective move: it must change nothing and record no undo.
        board.swipeUp()
        XCTAssertEqual(title.frame.origin.y, titleBefore.origin.y, accuracy: 1.0,
                       "a board swipe must not move the surrounding screen")
        XCTAssertEqual(board.frame.origin.y, boardBefore.origin.y, accuracy: 1.0,
                       "the board must stay anchored during a swipe")
        XCTAssertFalse(app.buttons["Undo"].isEnabled,
                       "an ineffective move must not create undo history")

        // Down is a valid move for this fixture, so it must register.
        board.swipeDown()
        XCTAssertEqual(title.frame.origin.y, titleBefore.origin.y, accuracy: 1.0,
                       "a downward board swipe must not drag the page either")
        XCTAssertTrue(app.buttons["Undo"].isEnabled,
                      "a valid vertical swipe must reach the board")
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
