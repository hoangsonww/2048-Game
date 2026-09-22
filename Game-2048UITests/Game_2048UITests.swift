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

    /// The account surface opens, swaps forms, and gets out of the way.
    ///
    /// No request leaves the simulator here: a signed-out launch never calls
    /// the API, and none of these controls do either. What is being proved is
    /// that every sheet is reachable and dismissible, which is the part a
    /// unit test cannot see.
    func testAccountSheetsOpenSwapAndDismiss() {
        let app = launch()
        XCTAssertTrue(app.otherElements["GameBoard"].waitForExistence(timeout: 15))

        openSignIn(in: app)
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["identifierField"].exists)
        XCTAssertTrue(app.secureTextFields["passwordField"].exists)
        XCTAssertFalse(app.secureTextFields["confirmPasswordField"].exists,
                       "the header says Sign in, so it must open sign-in")

        app.buttons["authSwitch"].tap()
        XCTAssertTrue(app.staticTexts["Create your account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["usernameField"].exists)
        XCTAssertTrue(app.textFields["emailField"].exists)
        XCTAssertTrue(app.secureTextFields["passwordField"].exists)
        XCTAssertTrue(app.secureTextFields["confirmPasswordField"].exists,
                      "sign-up confirms the password; a typo there is unrecoverable")

        // Revealing a password swaps the secure field for a plain one.
        app.buttons["passwordFieldReveal"].tap()
        XCTAssertTrue(app.textFields["passwordField"].waitForExistence(timeout: 3))
        app.buttons["passwordFieldReveal"].tap()
        XCTAssertTrue(app.secureTextFields["passwordField"].waitForExistence(timeout: 3))

        // Return to sign-in for password recovery.
        app.buttons["authSwitch"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["confirmPasswordField"].exists)

        app.buttons["authForgot"].tap()
        XCTAssertTrue(app.staticTexts["Reset your password"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["resetUsernameField"].exists)
        XCTAssertTrue(app.secureTextFields["resetPasswordField"].exists)
        XCTAssertTrue(app.secureTextFields["resetConfirmField"].exists)

        app.buttons["resetDismiss"].tap()
        XCTAssertFalse(app.staticTexts["Reset your password"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["GameBoard"].waitForExistence(timeout: 5))
    }

    /// A mismatched confirmation is refused before anything is sent.
    func testSignUpRefusesAMismatchedConfirmation() {
        let app = launch()
        XCTAssertTrue(app.otherElements["GameBoard"].waitForExistence(timeout: 15))

        // The invite toast intentionally auto-hides after 5.5 seconds, which
        // can elapse while a loaded simulator establishes its UI session.
        // Enter through the persistent Sign in control, then take the
        // explicit registration switch.
        openSignIn(in: app)
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        app.buttons["authSwitch"].tap()
        XCTAssertTrue(app.staticTexts["Create your account"].waitForExistence(timeout: 5))
        // Xcode 16's UI runner intermittently sends only the first character
        // to a SwiftUI SecureField. Reveal each field before typing so this
        // test exercises an actual mismatch on every supported runner rather
        // than accidentally submitting the equal pair "P" / "P".
        //
        // Sign-up is tall enough that the confirmation field sits under the
        // keyboard after the first password is typed; a bare tap then fails
        // CI with "Neither element nor any descendant has keyboard focus".
        typeIntoRevealedPassword(identifier: "passwordField", text: "Password1", in: app)
        typeIntoRevealedPassword(identifier: "confirmPasswordField", text: "Password2", in: app)
        app.buttons["authSubmit"].tap()

        // SwiftUI exposes a `Label` as a static text on newer runtimes but as
        // a combined accessibility element on iOS 18/Xcode 16. Query by the
        // identifier rather than tying this assertion to either element type.
        XCTAssertTrue(element(identifier: "passwordMismatch", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Create your account"].exists, "the form stays up to be corrected")
    }

    /// Signing in with a round on screen asks before taking it away.
    func testSigningInMidRoundWarnsBeforeTheBoardLeavesTheScreen() {
        let app = launch(state: "merge")
        let board = app.otherElements["GameBoard"]
        XCTAssertTrue(board.waitForExistence(timeout: 15))
        board.swipeLeft()
        XCTAssertTrue(app.buttons["Undo"].isEnabled)

        openSignIn(in: app)
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        app.textFields["identifierField"].tap()
        app.textFields["identifierField"].typeText("ada")
        app.secureTextFields["passwordField"].tap()
        app.secureTextFields["passwordField"].typeText("Password1")
        app.buttons["authSubmit"].tap()

        let warning = app.alerts["Set this round aside?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        warning.buttons["Keep playing"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5),
                      "declining leaves the form up and the round alone")
    }

    func testLaunchPerformance() {
        let app = XCUIApplication()
        app.launchEnvironment["GAME2048_UI_TESTING"] = "1"
        measure(metrics: [XCTApplicationLaunchMetric()]) { app.launch() }
    }

    @discardableResult
    private func launch(state: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["GAME2048_UI_TESTING"] = "1"
        if let state { app.launchEnvironment["GAME2048_UI_TEST_STATE"] = state }
        app.launch()
        return app
    }

    /// Opens the credential sheet from a guest session.
    ///
    /// A leftover simulator login would otherwise open Account, and these
    /// cases are about the sign-in / sign-up forms, not the signed-in panel.
    private func openSignIn(in app: XCUIApplication) {
        app.buttons["accountButton"].tap()
        if app.buttons["signOutButton"].waitForExistence(timeout: 2) {
            app.buttons["signOutButton"].tap()
            XCTAssertTrue(app.otherElements["GameBoard"].waitForExistence(timeout: 5))
            app.buttons["accountButton"].tap()
        }
    }

    /// Types into a revealed password field without losing keyboard focus.
    ///
    /// On the taller sign-up form the confirmation field lands under the
    /// keyboard once the first password is focused. CI then fails
    /// `typeText` with "Neither element nor any descendant has keyboard
    /// focus" even though the field exists and was tapped. Reveal already
    /// claims focus in the app; wait for that before typing, and only tap
    /// the field as a fallback after scrolling it clear of the keyboard.
    private func typeIntoRevealedPassword(identifier: String, text: String, in app: XCUIApplication) {
        let reveal = app.buttons["\(identifier)Reveal"]
        let field = app.textFields[identifier]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))

        // Clear any prior keyboard so the next reveal can claim a visible field.
        if app.keyboards.firstMatch.exists {
            app.swipeDown()
            let gone = NSPredicate(format: "exists == false")
            let wait = XCTNSPredicateExpectation(predicate: gone, object: app.keyboards.firstMatch)
            _ = XCTWaiter.wait(for: [wait], timeout: 2)
        }

        reveal.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            if field.frame.maxY > app.frame.midY {
                app.swipeUp()
            }
            field.tap()
            if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        }

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "\(identifier) should accept keyboard input")
        field.typeText(text)
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
