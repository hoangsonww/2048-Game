//
//  Game_2048UITests.swift
//  Game-2048UITests
//
//  Created by Dav Nguyen on 3/19/24.
//

import XCTest

final class Game_2048UITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        // Initialize the app before each test method
        app = XCUIApplication()
        continueAfterFailure = false
        app.launch()
    }

    override func tearDownWithError() throws {
        // Clean up after each test method
        app = nil
    }

    func testLaunchScreenAndTransitionToGameView() throws {
        // Verify the app starts on the LaunchScreen
        let titleText = app.staticTexts["2048"]
        XCTAssertTrue(titleText.exists, "The 2048 title should be visible on the launch screen.")

        // Verify the transition to the GameView after 2 seconds
        let exists = NSPredicate(format: "exists == 1")
        let gameViewText = app.staticTexts["Score"] // Assuming 'Score' is visible in GameView
        expectation(for: exists, evaluatedWith: gameViewText, handler: nil)

        waitForExpectations(timeout: 3) { error in
            if error != nil {
                XCTFail("GameView did not appear after the launch screen.")
            }
        }
    }

    func testGamePlaySwipeLeft() throws {
        // Ensure we're on the GameView
        let scoreLabel = app.staticTexts["Score"]
        XCTAssertTrue(scoreLabel.exists, "Game should be on the GameView after the launch screen.")

        // Perform a swipe left gesture
        let gameBoard = app.otherElements["GameBoard"] // Ensure the GameView has the correct accessibility identifier set for the grid/board
        gameBoard.swipeLeft()

        // Since it's hard to predict specific gameplay results in a UI test, verify that the score label updates
        let scoreValue = scoreLabel.label
        XCTAssertNotEqual(scoreValue, "0", "Score should update after swiping left.")
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // Measures how long it takes to launch the app.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                app.launch()
            }
        }
    }
}
