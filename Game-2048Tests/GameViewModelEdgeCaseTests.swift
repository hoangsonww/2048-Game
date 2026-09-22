import XCTest
@testable import Game_2048

/// Boundary coverage for the iOS rules engine.
///
/// `GameViewModelTests` proves the ordinary paths. These pin the edges where a
/// subtle change would still pass every ordinary test but break real rounds:
/// merge ordering per direction, undo depth, spawn clamping, persistence
/// round-trips, and the exact predicates for winning and losing.
///
/// Every game here uses a deterministic tile provider, so a spawned tile lands
/// in a known cell and whole-board assertions stay stable.
final class GameViewModelEdgeCaseTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "GameViewModelEdgeCaseTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Merge ordering

    func testAMergedTileCannotMergeAgainInTheSameMove() {
        // [2,2,4] moving left is [4,4] and never [8]. This is the single most
        // commonly broken 2048 rule.
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 4, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(Array(game.grid[0].prefix(2)), [4, 4])
        XCTAssertEqual(game.score, 4)
    }

    func testFourEqualTilesMakeTwoPairsNotOneChain() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 2, 2], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(Array(game.grid[0].prefix(2)), [4, 4])
        XCTAssertEqual(game.score, 8, "two separate merges, not a chain into 8")
    }

    func testLeftMergesThePairNearestTheDestinationEdge() {
        let game = makeGame()
        game.setGameForTesting(grid: [[0, 2, 2, 2], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        // The spawn lands in the first empty cell, so assert the merge itself.
        XCTAssertEqual(game.grid[0][0], 4)
        XCTAssertEqual(game.grid[0][1], 2)
        XCTAssertEqual(game.score, 4)
    }

    func testRightMergesFromTheFarEdgeInward() {
        // [2,2,2,0] moving right is 2 then 4 against the right edge: the pair
        // nearest the destination merges first, the opposite of moving left.
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 2, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .right))
        XCTAssertEqual(game.grid[0][2], 2)
        XCTAssertEqual(game.grid[0][3], 4)
        XCTAssertEqual(game.score, 4)
    }

    func testUpMergesColumnsFromTheTopDown() {
        let game = makeGame(randomIndex: { $0 - 1 })
        game.setGameForTesting(grid: [[2, 0, 0, 0], [2, 0, 0, 0], [2, 0, 0, 0], zeros])
        XCTAssertTrue(game.swipe(direction: .up))
        XCTAssertEqual(game.grid[0][0], 4)
        XCTAssertEqual(game.grid[1][0], 2)
        XCTAssertEqual(game.score, 4)
    }

    func testDownMergesColumnsFromTheBottomUp() {
        let game = makeGame(randomIndex: { $0 - 1 })
        game.setGameForTesting(grid: [[2, 0, 0, 0], [2, 0, 0, 0], [2, 0, 0, 0], zeros])
        XCTAssertTrue(game.swipe(direction: .down))
        XCTAssertEqual(game.grid[2][0], 2)
        XCTAssertEqual(game.grid[3][0], 4)
        XCTAssertEqual(game.score, 4)
    }

    func testEachDirectionMovesASingleTileToItsFarEdge() {
        for (direction, expected) in [
            (GameViewModel.Direction.up, (0, 1)),
            (.down, (3, 1)),
            (.left, (1, 0)),
            (.right, (1, 3))
        ] {
            let game = makeGame(randomIndex: { $0 - 1 })
            game.setGameForTesting(grid: [zeros, [0, 2, 0, 0], zeros, zeros])
            XCTAssertTrue(game.swipe(direction: direction))
            XCTAssertEqual(game.grid[expected.0][expected.1], 2, "\(direction) should land the tile at \(expected)")
        }
    }

    // MARK: - Scoring

    func testScoreCountsOnlyNewlyCreatedTiles() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 8, 8], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.score, 20, "4 + 16, and nothing for the tiles that only slid")
    }

    func testSlidingWithoutMergingScoresNothing() {
        let game = makeGame()
        game.setGameForTesting(grid: [[0, 0, 2, 4], zeros, zeros, zeros], score: 12)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.score, 12)
    }

    func testMergesAcrossSeveralRowsAllScoreInOneMove() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], [4, 4, 0, 0], [8, 8, 0, 0], zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.score, 28, "4 + 8 + 16")
    }

    func testAnIneffectiveMoveDoesNotLeakScore() {
        // mergeLine adds to score as it runs, so a rejected move has to roll
        // that back or a blocked swipe would quietly inflate the total.
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 4, 8, 16], zeros, zeros, zeros], score: 40)
        XCTAssertFalse(game.swipe(direction: .left))
        XCTAssertEqual(game.score, 40)
    }

    // MARK: - Ineffective moves

    func testEveryDirectionIsIneffectiveOnAnEmptyBoard() {
        let game = makeGame()
        game.setGameForTesting(grid: [zeros, zeros, zeros, zeros])
        for direction in allDirections {
            XCTAssertFalse(game.swipe(direction: direction), "\(direction) must not register on an empty board")
        }
        XCTAssertFalse(game.canUndo)
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 0, "no tile may spawn")
    }

    func testABlockedDirectionCreatesNoUndoHistory() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 4, 8, 16], zeros, zeros, zeros])
        XCTAssertFalse(game.swipe(direction: .left))
        XCTAssertFalse(game.canUndo, "an ineffective move must not be undoable")
    }

    // MARK: - Undo

    func testUndoIsExactlyOneStepDeep() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        let afterFirst = game.grid
        let scoreAfterFirst = game.score

        XCTAssertTrue(game.swipe(direction: .right))
        game.undo()

        XCTAssertEqual(game.grid, afterFirst)
        XCTAssertEqual(game.score, scoreAfterFirst)
        XCTAssertFalse(game.canUndo, "the snapshot is consumed, so undo cannot repeat")

        game.undo()
        XCTAssertEqual(game.grid, afterFirst, "a second undo is a no-op")
    }

    func testUndoOnAFreshRoundDoesNothing() {
        let game = makeGame()
        let before = game.grid
        game.undo()
        XCTAssertEqual(game.grid, before)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoRestoresTheWinStateThatPrecededTheMove() {
        let game = makeGame()
        game.setGameForTesting(grid: [[1024, 1024, 0, 0], zeros, zeros, zeros], hasWon: false)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertTrue(game.hasWon)

        game.undo()
        XCTAssertFalse(game.hasWon, "undoing the winning move rewinds the win state too")
    }

    func testRestartClearsUndoHistory() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertTrue(game.canUndo)

        game.restartGame()
        XCTAssertFalse(game.canUndo, "a new round must not be undoable into the previous one")
    }

    // MARK: - Win and loss predicates

    func testReachingTwoThousandFortyEightWinsButKeepsPlaying() {
        let game = makeGame()
        game.setGameForTesting(grid: [[1024, 1024, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertTrue(game.hasWon)
        XCTAssertEqual(game.grid[0][0], 2048)
        XCTAssertFalse(game.isGameOver(), "the board still has empty cells")
    }

    func testTheWinStateSticksOnceEarned() {
        let game = makeGame()
        // The gap makes the move effective; a board already flush left would be
        // rejected and would prove nothing about the win state.
        game.setGameForTesting(grid: [[2048, 0, 4, 0], zeros, zeros, zeros], hasWon: true)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertTrue(game.hasWon, "play continues after 2048 without losing the win")
    }

    func testAFullBoardWithAHorizontalPairIsNotOver() {
        let game = makeGame()
        game.setGameForTesting(grid: [
            [2, 2, 4, 8],
            [4, 8, 16, 32],
            [8, 16, 32, 64],
            [16, 32, 64, 128]
        ])
        XCTAssertFalse(game.isGameOver())
    }

    func testAFullBoardWithAVerticalPairIsNotOver() {
        let game = makeGame()
        game.setGameForTesting(grid: [
            [2, 4, 8, 16],
            [2, 8, 16, 32],
            [8, 16, 32, 64],
            [16, 32, 64, 128]
        ])
        XCTAssertFalse(game.isGameOver())
    }

    func testAFullBoardWithNoAdjacentPairIsOverAndRejectsEveryMove() {
        let game = makeGame()
        game.setGameForTesting(grid: [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 2]
        ])
        XCTAssertTrue(game.isGameOver())
        for direction in allDirections {
            XCTAssertFalse(game.swipe(direction: direction), "\(direction) must be rejected on a locked board")
        }
    }

    func testAnEmptyCellAlwaysMeansTheGameIsLive() {
        let game = makeGame()
        game.setGameForTesting(grid: [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 0]
        ])
        XCTAssertFalse(game.isGameOver())
    }

    // MARK: - Spawning

    func testAValidMoveSpawnsExactlyOneTile() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        // Two tiles merged into one, then exactly one spawned.
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2)
    }

    func testSpawnedTileHonoursTheNinetyTenSplitAtItsBoundary() {
        let two = makeGame(randomUnit: { 0.899999 })
        two.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(two.swipe(direction: .left))
        XCTAssertTrue(two.grid.flatMap { $0 }.contains(2))

        let four = makeGame(randomUnit: { 0.9 })
        four.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(four.swipe(direction: .left))
        XCTAssertTrue(four.grid.flatMap { $0 }.contains(4), "0.9 is not below 0.9, so a four spawns")
    }

    func testAnOutOfRangeSpawnIndexIsClampedIntoTheBoard() {
        // The provider is injectable, so the engine has to defend against an
        // index outside the empty-cell list rather than trapping.
        for index in [-5, 999] {
            let game = makeGame(randomIndex: { _ in index })
            game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
            XCTAssertTrue(game.swipe(direction: .left))
            XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2, "index \(index) must still place one tile")
        }
    }

    func testANewRoundStartsWithTwoDistinctTiles() {
        // Both spawns ask for the first empty cell; the second must see a
        // shorter list because the first already filled one.
        let game = makeGame(randomIndex: { _ in 0 })
        game.restartGame()
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2, "the two spawns must not collide")
    }

    // MARK: - Persistence

    func testASavedRoundRestoresBoardScoreAndWinState() {
        let first = makePersistingGame()
        first.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros], score: 40, hasWon: true)
        // The move has to be effective: a rejected swipe persists nothing.
        XCTAssertTrue(first.swipe(direction: .left))

        let restored = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(restored.grid, first.grid)
        XCTAssertEqual(restored.score, first.score)
        XCTAssertEqual(restored.hasWon, first.hasWon)
    }

    func testUndoIsPersistedSoRelaunchingDoesNotResurrectTheMove() {
        let first = makePersistingGame()
        first.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(first.swipe(direction: .left))
        XCTAssertTrue(first.swipe(direction: .right))
        first.undo()

        let restored = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(restored.grid, first.grid, "the undone board is what gets reloaded")
        XCTAssertEqual(restored.score, first.score)
    }

    func testASavedBoardOfTheWrongSizeIsDiscarded() {
        defaults.set(Array(repeating: 2, count: 9), forKey: "savedGridV2")
        defaults.set(500, forKey: "savedScoreV2")

        let game = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(game.grid.count, 4)
        XCTAssertTrue(game.grid.allSatisfy { $0.count == 4 })
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2, "a fresh round replaces the corrupt one")
        XCTAssertEqual(game.score, 0)
    }

    func testASavedBoardWithNonPowerOfTwoTilesIsDiscarded() {
        var values = Array(repeating: 0, count: 16)
        values[3] = 5
        defaults.set(values, forKey: "savedGridV2")

        let game = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2)
        XCTAssertFalse(game.grid.flatMap { $0 }.contains(5))
    }

    func testASavedBoardWithANegativeTileIsDiscarded() {
        var values = Array(repeating: 0, count: 16)
        values[0] = -2
        defaults.set(values, forKey: "savedGridV2")

        let game = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertFalse(game.grid.flatMap { $0 }.contains(-2))
    }

    func testANonNumericSavedBoardIsDiscarded() {
        defaults.set(["2", "4", "8"], forKey: "savedGridV2")

        let game = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2)
    }

    func testANegativeSavedScoreIsClampedRatherThanRestored() {
        defaults.set(Array(repeating: 0, count: 16), forKey: "savedGridV2")
        defaults.set(-99, forKey: "savedScoreV2")

        let game = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(game.score, 0)
    }

    func testANegativeStoredBestScoreIsClampedToZero() {
        defaults.set(-1000, forKey: "highScore")
        let game = GameViewModel(loadSavedGame: false, defaults: defaults)
        XCTAssertEqual(game.highScore, 0)
    }

    func testTheBestScoreSurvivesARestartAndNeverDecreases() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros], score: 100)
        XCTAssertTrue(game.swipe(direction: .left))
        let best = game.highScore
        XCTAssertGreaterThanOrEqual(best, 100)

        game.restartGame()
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.highScore, best, "a new round must not lower the best score")

        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros], score: 1)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.highScore, best, "a worse round must not overwrite the best score")
    }

    func testAGameThatDoesNotSaveLeavesNoStoredRound() {
        let game = GameViewModel(loadSavedGame: false, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertNil(defaults.array(forKey: "savedGridV2"), "a preview game must not write over a real round")
    }

    // MARK: - Helpers

    private let zeros = [0, 0, 0, 0]

    private var allDirections: [GameViewModel.Direction] { [.up, .down, .left, .right] }

    private func makeGame(
        randomIndex: @escaping (Int) -> Int = { _ in 0 },
        randomUnit: @escaping () -> Double = { 0 }
    ) -> GameViewModel {
        GameViewModel(loadSavedGame: false, defaults: defaults, randomIndex: randomIndex, randomUnit: randomUnit)
    }

    /// `loadSavedGame` is also the write switch: a game built with `false` is a
    /// throwaway preview and deliberately never persists. Persistence tests
    /// therefore need the loading flavour.
    private func makePersistingGame() -> GameViewModel {
        GameViewModel(loadSavedGame: true, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
    }
}

// MARK: - Maintainer reference (documentation only)
//
// Test strategy, deterministic fixtures, and CI reference.
//
// This section is intentionally comment-only. The named repository files remain
// canonical; their contents are mirrored here as an in-source reading reference.
// No declaration, executable statement, build setting, or runtime behavior follows.

// SOURCE: docs/testing.md

// # Testing and quality gates
//
// This document describes what is tested, where, how to run it, and how to tell a real defect from a flaky harness. Read it before changing tests or CI.
//
// ## Table of contents
//
// - [Testing philosophy](#testing-philosophy)
// - [Test inventory](#test-inventory)
// - [Fast checks](#fast-checks)
// - [Web](#web)
// - [iOS](#ios)
// - [Android](#android)
// - [Determinism](#determinism)
// - [Manual UI review](#manual-ui-review)
// - [CI mapping](#ci-mapping)
// - [Diagnosing failures](#diagnosing-failures)
// - [Adding a test](#adding-a-test)
//
// ## Testing philosophy
//
// Coverage is layered by cost. Pure rules logic is tested exhaustively because it is cheap, fast, and where correctness actually lives. The expensive suites — a real browser, a booted simulator, a running emulator — are reserved for the things unit tests genuinely cannot reach: gesture handling, persistence across a real relaunch, dialog behavior, focus, and accessibility semantics.
//
// Two consequences follow, and both are deliberate:
//
// - **A rules bug should be caught by a unit test, not a UI test.** If a rules regression is only detected in Chromium or on an emulator, the unit suite has a gap worth closing.
// - **A UI test should assert a user-visible outcome**, not re-derive the rules. Duplicating rules assertions in slow suites buys nothing and triples the maintenance cost of every rules change.
//
// ## Test inventory
//
// | Platform | Deterministic tests | UI / integration tests | Runner | Line coverage |
// | --- | --- | --- | --- | --- |
// | Web | 238 engine, controller, cloud, sound, metadata, and asset tests + 2 tooling tests | 13 Chromium scenarios | Node test runner, Playwright | 100 % |
// | iOS | 170 model/surface/cloud/profile tests | 13 XCUITest executions | XCTest | 95.1 % domain (gated at 90 %) |
// | Android | 193 ViewModel, storage, sound, and surface tests | 20 Compose instrumentation tests | JUnit 4, Compose UI Test | 97.2 % (domain) |
// | Cloud API | 76 unit tests | 27 integration tests against a real MongoDB | Node test runner, supertest | — |
//
// The iOS UI suite reports one extra execution because the launch test runs once per appearance mode. The Cloud API integration suite is skipped unless `MONGODB_TEST_URI` is set; see [backend.md](backend.md#local-development).
//
// All three deterministic suites prove the same behavioral contract from [`architecture.md`](architecture.md): every direction, merge ordering and the single-merge rule, scoring, weighted spawning, ineffective moves, undo semantics, restart, best-score retention, win and loss predicates, and rejection of invalid saved state.
//
// Each platform additionally covers the layer above its rules engine:
//
// - **Web** — the controller (`Web-Version/script.js`) runs against a hand-written DOM in `tests/web/helpers/fake-dom.js`, so keyboard, touch, buttons, rendering, and persistence are unit-tested without a browser.
// - **iOS** — persistence round-trips, spawn-index clamping, and corrupt `UserDefaults` payloads.
// - **Android** — `SharedPreferencesGameStorage` serialisation against an in-memory `SharedPreferences`.
// - **Both native clients** — the server-driven surface layer: decoding, version gating, node pruning, source fallback, and the rule that every failure mode ends at the app's own native UI. The shipped `help.json` payload is validated like any other untrusted input, and a test asserts the iOS and Android copies have not drifted apart.
// - **Cloud clients (all three platforms)** — fake-transport unit tests for auth, token refresh, sync resolutions, and the guest-prompt / controller state machine. The live API is covered by `server/` unit and integration suites, not by device tests.
// - **Guest and account profiles (all three platforms)** — that signing in parks the guest round rather than uploading it, that playing signed in never writes to the guest slot, that signing out restores the guest round byte for byte, and that career statistics are never lifted from local storage. See [Profile separation](#profile-separation).
// - **Sound (all three platforms)** — that cues are dropped rather than queued when they cannot be played now. See [Sound timing](#sound-timing).
//
// Every suite enforces its own coverage floor; see the platform sections below.
//
// ## Fast checks
//
// Run `make check` before committing. It validates:
//
// - JavaScript syntax across the engine, web script, and all `scripts/*.mjs`
// - JSON well-formedness for `manifest.json` and configuration files
// - Repository structure and the required npm script surface
// - SEO and discovery metadata — canonical URLs, `sitemap.xml` entries, the `robots.txt` sitemap directive, `llms.txt` availability
// - Referenced asset existence, including every icon named by the manifest and `index.html`
// - Staged-file whitespace, when invoked through Husky
// - Every shell script in `scripts/` and `.husky/`, when ShellCheck is installed
//
// ShellCheck is optional locally but **required in CI**. Install it (`brew install shellcheck`, or `apt-get install shellcheck`) to catch shell issues before pushing rather than after.
//
// This is the same command the Husky `pre-commit` hook runs, so a clean `make check` means a clean commit.
//
// ## Web
//
// ```bash
// npx playwright install chromium   # one-time
// make test-web                     # or: npm test
// ```
//
// `make test-web` runs, in order: syntax checks, repository validation, deterministic engine tests with enforced coverage, repository tooling tests, and real Chromium interaction flows.
//
// **Coverage is a hard gate.** `c8` fails the build below 100 % statements, 100 % lines, 100 % functions, or 95 % branches, measured against everything in `Web-Version/`. Both files currently reach 100 % statements, lines, and functions with 98.8 % branches. If you add web code, add the tests that keep it above the line — lowering the thresholds is not the fix.
//
// The controller is an IIFE that reads the document once on load, so `tests/web/helpers/fake-dom.js` stands in for the page: it captures the elements the controller looks up, records the listeners it registers, and lets a test fire a keypress, a swipe, or a click and read the result back. Each `loadController()` call re-requires the module, so tests never share state. The globals it installs are restored around every interaction, which is what keeps two loaded controllers independent.
//
// The thirteen Chromium scenarios cover arrow-key play, WASD play, touch swipe, the on-screen direction pad, undo, persistence across reload, restart confirmation, fullscreen, the win overlay, the loss overlay, recovery from a corrupt saved state, sound timing, account and password flows, and responsive layout from a 320 px phone through tablet widths.
//
// Browser tests drive the page through real input events and read state back through `window.render_game_to_text()`. Keep that hook accurate when the state shape changes, or the browser suite silently loses its assertions.
//
// Screenshots:
//
// ```bash
// make screenshots-web
// make screenshots-mobile       # requires booted iOS + Android runtimes
// ```
//
// `make screenshots-web` captures deterministic desktop and mobile views of gameplay, the restart dialog, win, loss, About, and the cloud surfaces. `make screenshots-mobile` drives the native clients through accessibility-labelled controls and promotes their game, guest, auth, handover, reset, and leaderboard states. The QA-only variants keep reproducible evidence under `output/playwright/latest/` and `output/mobile/`; those directories are gitignored and must not be committed.
//
// ## iOS
//
// ```bash
// make test-ios
// ```
//
// Requires macOS with Xcode. The script selects an available iPhone simulator automatically; pin a specific device by setting `IOS_SIMULATOR_ID` to a UDID from `xcrun simctl list devices available`.
//
// Model tests and UI tests run as separate targets (`Game-2048Tests` and `Game-2048UITests`) so a UI-harness failure never masks a rules regression. Preserve the `.xcresult` bundle when diagnosing a failure — it carries the failure screenshots, the full test log, and coverage data that the console output does not.
//
// **Coverage is a hard gate.** After the run, `scripts/test-ios.sh` reads the `.xcresult` with `xccov` and fails below 90 % line coverage of stable app/domain code, currently 95.1 %. `GameView.swift` and `CloudViews.swift` are excluded from the numeric gate because Xcode versions expose materially different generated executable-line counts for SwiftUI view builders. Their behavior is covered by the simulator suite, the same posture Android takes for `MainActivity` and `CloudUi`. Override the floor with `IOS_MINIMUM_COVERAGE` only to raise it.
//
// **Coverage must be measured on both suites together.** The local script runs one combined `xcodebuild test`, and CI — which runs the two targets separately so a UI-harness failure cannot mask a rules regression — collects coverage from both and merges the result bundles with `xcrun xcresulttool merge` before gating. UI-driven paths outside the excluded SwiftUI presentation files therefore still contribute to the domain gate.
//
// New test files must be added to the `Game-2048Tests` target in `2048 Game.xcodeproj` — the project does not use synchronised file groups, so a file that is merely on disk is silently never compiled or run.
//
// XCUITest depends on accessibility identifiers. If a UI test starts failing after a view change, confirm the identifier still exists before assuming the behavior broke.
//
// ## Android
//
// ```bash
// make test-android          # unit tests, lint, debug APK
// make test-android-device   # adds Compose tests on a connected device
// ```
//
// **Coverage is a hard gate.** `make test-android` runs `jacocoCoverageVerification`, which fails below 90 % line or 85 % branch coverage of the Kotlin rules engine and its storage (`GameViewModel`, `GameStorage`, `SavedGame`, `SharedPreferencesGameStorage`, and the `sdui` package). Those currently sit at 97.2 % lines and 85.7 % branches. `SurfaceCatalog` is excluded for the same reason `MainActivity` is — it needs a real `Context`. The HTML report lands in `app/build/reports/jacoco/jacocoTestReport/`.
//
// `MainActivity` is Compose and is deliberately outside that gate: it can only be exercised on a device, which `make test-android-device` does. Holding the whole module to a JVM-only threshold would either fail on every machine without an emulator or push the number down to something meaningless.
//
// The JVM suite needs only the Android SDK 34 — **not a preinstalled JDK.** Gradle 8.13 daemon JVM criteria are committed in `Android-Version/Game2048/gradle/gradle-daemon-jvm.properties`, so Gradle downloads and runs on a matching Adoptium JDK 17 regardless of the machine's default `java`. The first invocation pays a one-time ~180 MB download into `~/.gradle/jdks/`.
//
// `scripts/android.sh` additionally resolves a JDK 17 up front, so both the `make` targets and a raw `./gradlew` work on a machine whose `JAVA_HOME` points at the wrong version.
//
// The instrumentation suite additionally needs a booted emulator or attached device — CI uses an API 34 `pixel_6` image with KVM acceleration and animations disabled.
//
// Animations must be disabled on the device running Compose tests. Enabled animations are the most common cause of intermittent instrumentation failures, and they fail in ways that look like real defects.
//
// ## Dev container
//
// The dev container covers the web and Android JVM workflows. Verify it with:
//
// ```bash
// make verify-devcontainer                   # build the image, check every tool
// ./scripts/verify-devcontainer.sh --build   # also build the Android client inside it
// ```
//
// The `--build` form works on an isolated `git archive` copy rather than mounting the working tree. That matters: mounting the live repo means a container build and a host build write to the same `app/build/` directory at the same time, which produces confusing `packageDebug FAILED` errors that look like real defects but are pure contention. Never run both concurrently against the same tree.
//
// **iOS is not containerizable.** Xcode is macOS-only and its license forbids redistribution, so iOS builds and simulator tests always require a macOS host. `make doctor` reports this honestly rather than pretending the suite was skipped for another reason.
//
// ## Emulator health retries
//
// The Compose instrumentation suite runs on a hosted runner, where the emulator
// occasionally comes up degraded — the console fails to start, `adb` retries
// during boot, and the app process never hosts a Compose hierarchy. That
// presents as `IllegalStateException: No compose hierarchies found in the app`
// from whichever assertion happens to run first, which points at the test
// rather than at the device it is waiting on.
//
// Two mitigations, in order:
//
// 1. `GameScreenTest.show()` blocks until a Compose root actually registers, so
//    a *slow* launch waits instead of failing.
// 2. [`scripts/ci-emulator-tests.sh`](../scripts/ci-emulator-tests.sh) retries
//    the instrumentation run **once**, and only when the log carries an
//    emulator-health signature (`No compose hierarchies found`, `Failed to start
//    Emulator console`, `INSTALL_FAILED`, `Test run failed to complete`,
//    `Unable to find instrumentation`, `Could not access the Package Manager`).
//
// A third layer sits above both, because the first two can only help once the
// emulator exists. The action provisions it — SDK download, AVD creation, boot —
// before the script is reached, and that provisioning fails on its own
// occasionally (`Error on ZipFile unknown archive` from a corrupt package
// download). The step therefore gets one more attempt, gated on evidence rather
// than on assumption: if a connected-test **result file** exists, the suite ran
// and the failure is real, so it fails immediately. Only when nothing was
// reported at all — meaning the suite never started — is the environment
// retried. A failing test can never reach the second attempt.
//
// That logic lives in a script rather than inline workflow YAML because
// `reactivecircus/android-emulator-runner` runs its `script:` input **one line at
// a time, each in its own `sh -c`**. No variable survives between lines, and a
// multi-line `while` or `if` is split mid-statement and fails with
// `Syntax error: end of file unexpected`. Single-line commands are the only
// thing that input can express directly.
//
// The second is deliberately narrow. A failing assertion looks nothing like
// those signatures and fails on the first attempt — a retry that caught
// everything would convert a real regression into an intermittent one, which is
// worse than the flake it was meant to solve.
//
// ## Gesture ownership
//
// Every client has now shipped a bug where a board swipe reached the surrounding container instead of the game, and each had a different cause. These are the guards:
//
// - **Web:** a browser test asserts the board sets `touch-action: none`, that a `touchmove` starting on the board is `defaultPrevented`, that one starting elsewhere is **not**, and that `touchcancel` releases the suppression.
// - **iOS:** a UI test asserts `app.scrollViews` is empty, that the `"Make space."` title's frame does not move during a swipe, and that a valid vertical swipe enables Undo. Anchor on chrome *outside* the board: the container can move while the board's own frame appears stable.
// - **Android:** the Compose suite drives real swipes; the board must consume each pointer change so the parent scroll never sees it.
//
// When a swipe bug is reported, measure before theorising. Frame coordinates and the enabled state of Undo tell you whether input reached the game at all — a swipe that scrolls the page and a swipe that silently does nothing look identical to a user, and the second is the more serious defect.
//
// ## Profile separation
//
// A device holds two independent rounds — the guest one and the signed-in one —
// and the bug class here is leakage in either direction: an account inheriting a
// board it never played, or a session overwriting the round a player had before
// they signed in. Both are silent, and both are only visible a step later, when
// the numbers on the account panel do not match anything the player did.
//
// Each client asserts the same five properties against its own storage:
//
// 1. Starting a session parks the guest round untouched, and the account starts
//    on a clean board with no best score borrowed from the device.
// 2. Playing signed in writes only to the account slot.
// 3. Ending a session restores the guest round exactly — board, score, moves,
//    and best score — and clears the cached account round.
// 4. A sign-in offers the server a **null** save, so nothing local can reach the
//    account.
// 5. Career totals render the account's own figures, even when the device holds
//    a much higher local best.
//
// The web suite drives these through `window.Game2048Game`, iOS through
// `GameViewModel` against a scratch `UserDefaults` suite, and Android through
// two prefixed `SharedPreferencesGameStorage` slots over one fake preferences
// file. The warning dialog itself is covered at the UI level on all three:
// Playwright, XCTest's confirmation dialog, and the Compose suite.
//
// ## Credential entry
//
// Three properties, asserted per client:
//
// 1. The confirmation field exists on sign-up and not on sign-in, and a
//    mismatch is refused **before** any request is made.
// 2. A reveal control flips only its own field, and closing a form hides every
//    password again.
// 3. A reset sends the username, the email, and the new password; a refusal
//    keeps the form open with the reason on it, and a success revokes the
//    session this device held and lands the player back on sign-in.
//
// Web covers these in `account-ui.test.js` plus a Playwright pass over the real
// `<dialog>` stacking and the input `type` flip. iOS and Android assert the
// controller and API halves on the JVM / in XCTest, and the sheets themselves
// in the Compose and XCUITest suites. The server's own reset rules — that a
// mismatched pair is refused, that the refusal is indistinguishable from an
// unknown account, and that every session dies — are in
// `server/tests/integration/api.test.js`, which needs `MONGODB_TEST_URI`.
//
// ## Sound timing
//
// The defect these guard is not "no sound" — it is sound arriving late and all
// at once. Silence is easy to notice; a backlog is easy to ship.
//
// - **Web:** a Playwright test instruments `AudioContext`, asserts no context
//   exists before the first gesture, that the one built inside a gesture is
//   already running, that nothing is ever scheduled against a stopped clock, and
//   that twelve cues land on at least six distinct clock readings rather than
//   one. The unit suite covers the voice cap and the drop-rather-than-queue rule.
// - **iOS:** the cue renderer is a pure `nonisolated` function, so the envelope,
//   the frequency slide, and the degenerate zero-length case are testable with
//   no audio device.
// - **Android:** the mixer writes through an injected `ToneSink`, so a JVM test
//   can pace it like a real `AudioTrack` and assert that two hundred cues
//   produce a fraction of a second of audio rather than ten seconds of backlog.
//
// ## Determinism
//
// Every deterministic suite injects its own random provider, so tile spawning is fully reproducible. Never write a rules test that depends on real randomness, and never make the injectable provider the production default.
//
// Tests may also drive state through launch arguments (iOS) or launch state (Android) to reach a specific board — for example a nearly-lost board — without playing dozens of moves to get there. Prefer that over long scripted move sequences: it is faster and it fails more legibly.
//
// ## Manual UI review
//
// Automated coverage does not replace looking at the screen. `make screenshots-web` captures browser states at desktop and mobile widths; `make screenshots-mobile` captures the native equivalents from a simulator and emulator. Both promote the canonical set into `images/`:
//
// | Gameplay | Restart confirmation | Win |
// | :---: | :---: | :---: |
// | ![Normal gameplay with guest invite and cloud controls](../images/web-version-UI.png) | ![The confirmation dialog shown before replacing an active round](../images/web-restart-dialog.png) | ![The win overlay after reaching 2048](../images/web-win.png) |
//
// | Game over | Mobile layout | About |
// | :---: | :---: | :---: |
// | ![The game-over overlay on a locked board](../images/web-loss.png) | ![The mobile layout with on-screen direction controls](../images/web-mobile-gameplay.png) | ![The rules and strategy page](../images/web-about.png) |
//
// | Guest invite | Create account | Leaderboard |
// | :---: | :---: | :---: |
// | ![Guest banner above the board](../images/web-cloud-guest.png) | ![Create-account dialog](../images/web-cloud-signup.png) | ![Leaderboard dialog](../images/web-cloud-leaderboard.png) |
//
// | Account panel | Android guest | Android auth sheet |
// | :---: | :---: | :---: |
// | ![Signed-in account panel](../images/web-cloud-account.png) | ![Android guest banner](../images/android-cloud-guest.png) | ![Android create-account sheet](../images/android-cloud-signup.png) |
//
// | iOS auth sheet | iOS handover | Native password reset |
// | :---: | :---: | :---: |
// | ![iOS create-account sheet](../images/ios-cloud-signup.png) | ![iOS warning shown before setting the guest round aside](../images/ios-cloud-handover.png) | ![Android password-reset sheet](../images/android-cloud-reset.png) |
//
// For every changed surface, inspect normal gameplay, help/about, restart confirmation, win, game-over, and any touched cloud dialogs where applicable, and check:
//
// - Compact and large breakpoints
// - Icon centering, at every icon, by geometry rather than font metrics
// - Text truncation and wrapping at the longest realistic content
// - Contrast at every tile value, including the high-value tiles
// - Focus order and visible focus indicators
// - Touch-target sizes
// - Safe areas on iOS and gesture-navigation insets on Android
// - Browser console output and native crash logs — a clean-looking screen with console errors is still a failure
//
// UI changes require screenshots of the affected states, attached to the pull request.
//
// ## CI mapping
//
// | Job | Runner | Steps |
// | --- | --- | --- |
// | Web | `ubuntu-latest` | `npm ci`, `npm audit --audit-level=high`, Chromium install, syntax, repository validation, ShellCheck, unit + coverage, tooling, browser flows |
// | iOS | `macos-15` | Boot a simulator, `build-for-testing`, model tests with coverage, UI/accessibility tests |
// | Android JVM | `ubuntu-latest` | `testDebugUnitTest`, `lintDebug`, `assembleDebug` |
// | Android device | `ubuntu-latest` + KVM | API 34 `pixel_6` emulator, `connectedDebugAndroidTest` |
// | Dependency review | `ubuntu-latest` | Blocks pull requests introducing known-vulnerable dependencies |
//
// Artifacts uploaded on both success and failure: web coverage reports, iOS `.xcresult` bundles, Android lint and test reports, and the debug APK.
//
// The iOS and Android device jobs are the slow ones. When iterating, run the fast web suite locally and let CI carry the native suites rather than waiting on a local emulator boot for every change.
//
// ## Diagnosing failures
//
// **Before reporting an app defect, establish whether it is a harness failure.**
//
// | Symptom | Likely cause | Next step |
// | --- | --- | --- |
// | ADB loses the view hierarchy mid-run | Emulator/ADB instability | Check `adb logcat`, restart the emulator **without** wiping data, rerun the exact failing test |
// | Compose test fails intermittently only | Animations enabled on the device | Disable animations, then rerun |
// | XCUITest cannot find an element | Missing or renamed accessibility identifier | Confirm the identifier in the view, not the behavior |
// | Browser test times out waiting for state | `render_game_to_text()` shape drifted | Compare the hook output against the assertion |
// | Coverage step fails after a refactor | New engine branches are untested | Add the missing cases — do not lower the thresholds |
// | Simulator tests fail only in CI | Different default simulator/runtime | Reproduce with the same device the workflow selects |
//
// A test that fails once and passes on rerun with no code change is a flake, and flakes are bugs. File them rather than re-running until green.
//
// ## Adding a test
//
// 1. Put rules behavior in the **deterministic** suite for each platform — all three, since parity is the point.
// 2. Put user-flow behavior in the platform UI suite, asserting a user-visible outcome rather than re-deriving the rules.
// 3. Inject randomness. Never depend on real random spawning.
// 4. Prefer reaching a target board through injected state over a long scripted move sequence.
// 5. Name the test after the behavior it protects, not the function it calls — the name is what a future maintainer reads when it fails.
// 6. Confirm it fails before your fix and passes after. A test that never failed has proven nothing.
// 7. On iOS, add the file to the `Game-2048Tests` target in the Xcode project. A test file that is only on disk never runs and never fails.
//
// **A valid move always spawns a tile.** Asserting a whole row or board after a move therefore couples the test to wherever the injected provider happens to place that tile. Assert the cells the move itself produced, plus the score, unless the spawn position is deliberately pinned.
//
// **An ineffective move persists nothing.** A persistence test whose swipe is rejected saves no state and quietly proves nothing — assert that the move returned `true` before checking what was stored.

// SOURCE: .github/workflows/ci.yml

// name: Cross-platform CI
//
// on:
//   push:
//     branches: [main, master]
//   pull_request:
//   workflow_dispatch:
//
// permissions:
//   contents: read
//
// concurrency:
//   group: ci-${{ github.workflow }}-${{ github.ref }}
//   cancel-in-progress: true
//
// jobs:
//   web:
//     name: Web unit, coverage, and browser flows
//     runs-on: ubuntu-latest
//     timeout-minutes: 20
//     steps:
//       - name: Check out repository
//         uses: actions/checkout@v4
//
//       - name: Set up Node.js
//         uses: actions/setup-node@v4
//         with:
//           node-version: 22
//           cache: npm
//
//       - name: Install locked dependencies
//         run: npm ci
//
//       - name: Audit JavaScript dependencies
//         run: npm audit --audit-level=high
//
//       - name: Install Chromium and system dependencies
//         run: npx playwright install --with-deps chromium
//
//       - name: Validate JavaScript syntax
//         run: npm run check:syntax
//
//       - name: Validate repository and discovery metadata
//         run: npm run check:repo
//
//       - name: Lint project shell utilities
//         run: shellcheck -x -P scripts scripts/*.sh .husky/pre-commit .husky/pre-push
//
//       # VERSION is the only place a human edits it; package.json, the Android
//       # manifest, and the Xcode project are derived. They had drifted four ways
//       # — 1.2.0, 1.0, 1.0, and a v2.0.0 release — so the agreement is enforced
//       # rather than assumed.
//       - name: Version consistency
//         run: ./scripts/version.sh check
//
//       - name: Run rules, SEO, asset, and coverage tests
//         run: npm run test:unit
//
//       - name: Run repository tooling tests
//         run: npm run test:tooling
//
//       - name: Run browser interaction tests
//         run: npm run test:browser
//
//       - name: Upload web coverage report
//         if: always()
//         uses: actions/upload-artifact@v4
//         with:
//           name: web-coverage
//           path: coverage/
//           if-no-files-found: warn
//
//   ios:
//     name: iOS build, model tests, and UI flows
//     runs-on: macos-15
//     timeout-minutes: 45
//     steps:
//       - name: Check out repository
//         uses: actions/checkout@v4
//
//       - name: Report Xcode version
//         run: xcodebuild -version
//
//       - name: Select and boot an iPhone simulator
//         run: |
//           DEVICE_ID=$(xcrun simctl list devices available -j | jq -r '[.devices[][] | select(.name | startswith("iPhone"))][0].udid')
//           if [ -z "$DEVICE_ID" ] || [ "$DEVICE_ID" = "null" ]; then
//             echo "No available iPhone simulator found" >&2
//             exit 1
//           fi
//           xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
//           xcrun simctl bootstatus "$DEVICE_ID" -b
//           echo "IOS_DESTINATION=platform=iOS Simulator,id=$DEVICE_ID" >> "$GITHUB_ENV"
//
//       - name: Build app and test bundles
//         run: |
//           xcodebuild -project "2048 Game.xcodeproj" -scheme "Game-2048" \
//             -destination "$IOS_DESTINATION" -derivedDataPath "$RUNNER_TEMP/Game2048Derived" \
//             build-for-testing CODE_SIGNING_ALLOWED=NO -enableCodeCoverage YES
//
//       - name: Run Swift model tests with coverage
//         run: |
//           xcodebuild -project "2048 Game.xcodeproj" -scheme "Game-2048" \
//             -destination "$IOS_DESTINATION" -derivedDataPath "$RUNNER_TEMP/Game2048Derived" \
//             test-without-building -parallel-testing-enabled NO -only-testing:Game-2048Tests \
//             -resultBundlePath "$RUNNER_TEMP/iOS-Unit.xcresult" CODE_SIGNING_ALLOWED=NO -enableCodeCoverage YES
//
//       # ScreenshotTests only drives the simulator to capture images/ios-*.png;
//       # it asserts nothing, so it is skipped here as it is locally.
//       - name: Run iOS interaction and accessibility tests
//         run: |
//           xcodebuild -project "2048 Game.xcodeproj" -scheme "Game-2048" \
//             -destination "$IOS_DESTINATION" -derivedDataPath "$RUNNER_TEMP/Game2048Derived" \
//             test-without-building -parallel-testing-enabled NO -only-testing:Game-2048UITests \
//             -skip-testing:Game-2048UITests/ScreenshotTests \
//             -resultBundlePath "$RUNNER_TEMP/iOS-UI.xcresult" CODE_SIGNING_ALLOWED=NO -enableCodeCoverage YES
//
//       - name: Enforce app-target coverage
//         run: |
//           # The two suites run separately so a UI-harness failure cannot mask a
//           # rules regression, but coverage has to be judged on both together:
//           # GameView is exercised by XCUITest, so gating on the unit bundle
//           # alone measures something the local `make test-ios` does not.
//           xcrun xcresulttool merge \
//             "$RUNNER_TEMP/iOS-Unit.xcresult" "$RUNNER_TEMP/iOS-UI.xcresult" \
//             --output-path "$RUNNER_TEMP/iOS-Combined.xcresult"
//
//           file_report="$(xcrun xccov view --report --files-for-target Game-2048.app "$RUNNER_TEMP/iOS-Combined.xcresult")"
//           printf '%s\n' "$file_report" \
//             | awk 'NR>3 && NF { name=$2; sub(/.*\//, "", name); printf "  %-26s %s %s\n", name, $(NF-1), $NF }'
//
//           # Exclude SwiftUI presentation files from the numeric gate. Xcode
//           # versions expose different generated executable-line counts for
//           # view builders; the simulator suite exercises both views directly.
//           percent="$(printf '%s\n' "$file_report" | awk '
//             NR <= 3 { next }
//             NF < 3 { next }
//             {
//               file = $2
//               sub(/.*\//, "", file)
//               if (file == "CloudViews.swift" || file == "GameView.swift") next
//               hit_total = $NF
//               gsub(/[()]/, "", hit_total)
//               split(hit_total, parts, "/")
//               hit += parts[1] + 0
//               total += parts[2] + 0
//             }
//             END {
//               if (total == 0) exit 1
//               printf "%.2f", (hit / total) * 100
//             }
//           ')"
//           echo "Game-2048.app domain line coverage (excluding GameView.swift and CloudViews.swift): ${percent}%"
//
//           if [ -z "$percent" ]; then
//             echo "::error::Could not read a coverage percentage from the merged result bundle."
//             exit 1
//           fi
//
//           awk -v value="$percent" 'BEGIN { exit !(value < 90) }' \
//             && { echo "::error::Coverage ${percent}% is below the required 90%."; exit 1; }
//           echo "Coverage ${percent}% meets the 90% floor."
//
//       - name: Upload iOS result bundles
//         if: always()
//         uses: actions/upload-artifact@v4
//         with:
//           name: ios-test-results
//           path: |
//             ${{ runner.temp }}/iOS-Unit.xcresult
//             ${{ runner.temp }}/iOS-UI.xcresult
//           if-no-files-found: warn
//
//   android-jvm:
//     name: Android unit, lint, and APK build
//     runs-on: ubuntu-latest
//     timeout-minutes: 25
//     defaults:
//       run:
//         working-directory: Android-Version/Game2048
//     steps:
//       - name: Check out repository
//         uses: actions/checkout@v4
//
//       - name: Set up Java 17
//         uses: actions/setup-java@v4
//         with:
//           distribution: temurin
//           java-version: 17
//
//       - name: Set up and validate Gradle
//         uses: gradle/actions/setup-gradle@v4
//
//       - name: Run deterministic ViewModel and storage tests
//         run: ./gradlew testDebugUnitTest --stacktrace
//
//       - name: Enforce rules-engine coverage
//         run: ./gradlew jacocoCoverageVerification --stacktrace
//
//       - name: Run Android lint
//         run: ./gradlew lintDebug --stacktrace
//
//       - name: Assemble debug APK
//         run: ./gradlew assembleDebug --stacktrace
//
//       - name: Upload Android reports and APK
//         if: always()
//         uses: actions/upload-artifact@v4
//         with:
//           name: android-jvm-results
//           path: |
//             Android-Version/Game2048/app/build/reports/
//             Android-Version/Game2048/app/build/outputs/apk/debug/app-debug.apk
//           if-no-files-found: warn
//
//   android-device:
//     name: Android emulator UI flows
//     runs-on: ubuntu-latest
//     needs: android-jvm
//     timeout-minutes: 35
//     defaults:
//       run:
//         working-directory: Android-Version/Game2048
//     steps:
//       - name: Check out repository
//         uses: actions/checkout@v4
//
//       - name: Set up Java 17
//         uses: actions/setup-java@v4
//         with:
//           distribution: temurin
//           java-version: 17
//
//       - name: Set up and validate Gradle
//         uses: gradle/actions/setup-gradle@v4
//
//       - name: Enable KVM acceleration
//         run: |
//           echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
//           sudo udevadm control --reload-rules
//           sudo udevadm trigger --name-match=kvm
//
//       # The emulator is provisioned by the action itself — SDK download, AVD
//       # creation, boot — all before our script is reached. That provisioning
//       # fails on its own sometimes: a throttled or corrupt package download
//       # ("Error on ZipFile unknown archive") leaves no emulator at all, and no
//       # amount of care inside the test script can help, because the script
//       # never runs.
//       #
//       # So the step gets one more attempt — but only when the first attempt
//       # failed *without the suite ever reporting*. That distinction is the whole
//       # point, and it is checked against evidence on disk rather than assumed:
//       # a real test failure writes a connected-test report, an emulator that
//       # never came up writes nothing. A second attempt is therefore reachable
//       # only for a broken environment, never for a failing test.
//       - name: Run Compose tests on API 34
//         id: emulator
//         continue-on-error: true
//         uses: reactivecircus/android-emulator-runner@v2
//         with:
//           api-level: 34
//           arch: x86_64
//           target: google_apis
//           profile: pixel_6
//           disable-animations: true
//           # A hosted runner boots the emulator far more slowly than a laptop, and
//           # a half-booted device reports itself to adb before it can host an
//           # activity. Give the boot room, and refuse to start Gradle until the
//           # device says it is genuinely up.
//           emulator-boot-timeout: 900
//           emulator-options: -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -no-snapshot -camera-back none -camera-front none -no-metrics
//           working-directory: Android-Version/Game2048
//           # reactivecircus/android-emulator-runner runs this input one line at a
//           # time, each in its own `sh -c`: no variable survives between lines and
//           # any multi-line construct is split mid-statement. So the boot gate and
//           # the retry live in a script, invoked here as a single line. The path is
//           # relative to working-directory above.
//           script: ../../scripts/ci-emulator-tests.sh
//
//       - name: Decide whether that failure was the emulator or the tests
//         id: triage
//         if: steps.emulator.outcome == 'failure'
//         run: |
//           set -Eeuo pipefail
//           # Result files, not just the directories: an interrupted run can leave
//           # an empty directory behind, and that must not read as "the suite ran".
//           # Both locations are checked because AGP writes the machine-readable
//           # results and the HTML report to different trees.
//           produced="$(find app/build/outputs/androidTest-results/connected \
//                            app/build/reports/androidTests/connected \
//                            -type f \( -name '*.xml' -o -name '*.html' \) 2>/dev/null | head -1)"
//           if [ -n "$produced" ]; then
//             echo "The instrumentation suite ran and reported results ($produced),"
//             echo "so this is a real test failure. Not retrying — read the report artifact."
//             exit 1
//           fi
//           echo "No connected-test results exist, so the suite never ran and the"
//           echo "emulator was never usable. Retrying the environment once."
//           echo "retry=true" >> "$GITHUB_OUTPUT"
//
//       - name: Run Compose tests on API 34 (second attempt, unusable emulator)
//         if: steps.triage.outputs.retry == 'true'
//         uses: reactivecircus/android-emulator-runner@v2
//         with:
//           api-level: 34
//           arch: x86_64
//           target: google_apis
//           profile: pixel_6
//           disable-animations: true
//           # A hosted runner boots the emulator far more slowly than a laptop, and
//           # a half-booted device reports itself to adb before it can host an
//           # activity. Give the boot room, and refuse to start Gradle until the
//           # device says it is genuinely up.
//           emulator-boot-timeout: 900
//           emulator-options: -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -no-snapshot -camera-back none -camera-front none -no-metrics
//           working-directory: Android-Version/Game2048
//           # reactivecircus/android-emulator-runner runs this input one line at a
//           # time, each in its own `sh -c`: no variable survives between lines and
//           # any multi-line construct is split mid-statement. So the boot gate and
//           # the retry live in a script, invoked here as a single line. The path is
//           # relative to working-directory above.
//           script: ../../scripts/ci-emulator-tests.sh
//
//       - name: Upload Android instrumentation reports
//         if: always()
//         uses: actions/upload-artifact@v4
//         with:
//           name: android-device-results
//           path: Android-Version/Game2048/app/build/reports/androidTests/
//           if-no-files-found: warn
//
//   docker:
//     name: Docker image build and publish
//     runs-on: ubuntu-latest
//     timeout-minutes: 25
//     permissions:
//       contents: read
//       # Scoped to this job so the rest of the workflow keeps a read-only token.
//       packages: write
//     steps:
//       - name: Check out repository
//         uses: actions/checkout@v4
//
//       # arm64 is cross-built on an amd64 runner, which only works with binfmt
//       # handlers registered first.
//       - name: Set up QEMU
//         uses: docker/setup-qemu-action@v3
//
//       - name: Set up Buildx
//         uses: docker/setup-buildx-action@v3
//
//       # A pull request builds but never publishes. A fork's GITHUB_TOKEN cannot
//       # write packages anyway, and pushing an image built from unreviewed code
//       # to a tag other people pull is not something a green check should do.
//       - name: Decide whether this run publishes
//         id: mode
//         run: |
//           if [ "${{ github.event_name }}" = "pull_request" ]; then
//             echo "push=false" >> "$GITHUB_OUTPUT"
//             echo "Pull request: building only, not publishing."
//           else
//             echo "push=true" >> "$GITHUB_OUTPUT"
//             echo "Branch build: publishing to GHCR."
//           fi
//
//       # GHCR rejects an uppercase path, and the repository name is mixed case.
//       - name: Derive the image name
//         id: image
//         run: echo "name=ghcr.io/$(echo '${{ github.repository }}' | tr '[:upper:]' '[:lower:]')" >> "$GITHUB_OUTPUT"
//
//       - name: Collect tags and labels
//         id: meta
//         uses: docker/metadata-action@v5
//         with:
//           images: ${{ steps.image.outputs.name }}
//           tags: |
//             type=ref,event=branch
//             type=ref,event=pr
//             type=sha,format=long
//             type=raw,value=latest,enable={{is_default_branch}}
//
//       # Built and tested before anything is published, so a broken image cannot
//       # reach a tag someone else pulls. The publish step below reuses this
//       # layer cache, so proving it works costs little.
//       - name: Build the runner-architecture image
//         uses: docker/build-push-action@v6
//         with:
//           context: .
//           push: false
//           load: true
//           tags: 2048-smoke-test:${{ github.sha }}
//           cache-from: type=gha
//           cache-to: type=gha,mode=max
//
//       - name: Smoke test the image
//         run: |
//           set -Eeuo pipefail
//           docker run -d --name smoke -p 8080:8080 "2048-smoke-test:${{ github.sha }}"
//           for _ in $(seq 1 30); do
//             if curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1; then break; fi
//             sleep 1
//           done
//           echo "--- / must serve the game shell ---"
//           # Read the body into a variable rather than piping it into `grep -q`.
//           # `grep -q` exits at its first match — the <title> on line 6 — closing
//           # the pipe while curl still has the rest of the page to write. curl
//           # then dies of SIGPIPE with exit 23, `pipefail` propagates it, and the
//           # smoke test fails having proven the page was correct. Whether it
//           # happens at all depends on whether the whole body fitted in the pipe
//           # buffer, so it stayed dormant until index.html grew by one line.
//           shell="$(curl -fsS http://127.0.0.1:8080/)"
//           grep -q "<title>" <<< "${shell}"
//           echo "--- the engine and controller must be reachable ---"
//           curl -fsS http://127.0.0.1:8080/Web-Version/game-engine.js >/dev/null
//           curl -fsS http://127.0.0.1:8080/Web-Version/script.js >/dev/null
//           echo "--- discovery files and icons must be reachable ---"
//           curl -fsS http://127.0.0.1:8080/manifest.json >/dev/null
//           curl -fsS http://127.0.0.1:8080/images/favicon.svg >/dev/null
//           # --path-as-is stops curl collapsing the ".." itself, so the traversal
//           # reaches the server rather than being rewritten in the client.
//           #
//           # It is answered by the WHATWG URL parser, not by the resolve-and-
//           # compare guard in static-server.mjs: `new URL("/../x")` normalises
//           # the segment away, so `pathname` is already "/x" and the guard never
//           # fires. That makes the guard defence in depth against a future parser
//           # change rather than the active defence, which is worth knowing before
//           # anyone "simplifies" either half away. What this asserts is the
//           # outcome — a traversal never yields content — not the mechanism.
//           echo "--- a traversal must not escape the document root ---"
//           for path in "/../package.json" "/%2e%2e/package.json"; do
//             code="$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "http://127.0.0.1:8080${path}")"
//             echo "  ${path} -> ${code}"
//             test "$code" != "200"
//           done
//           echo "--- the container must not run as root ---"
//           test "$(docker exec smoke id -u)" != "0"
//           echo "Smoke test passed."
//           docker rm -f smoke
//
//       - name: Log in to GHCR
//         if: steps.mode.outputs.push == 'true'
//         uses: docker/login-action@v3
//         with:
//           registry: ghcr.io
//           username: ${{ github.actor }}
//           password: ${{ secrets.GITHUB_TOKEN }}
//
//       # The server is plain Node reading static files, so both architectures are
//       # honest builds rather than an emulated guess. amd64 is a cache hit from
//       # the smoke-test build above.
//       - name: Build both architectures and publish
//         uses: docker/build-push-action@v6
//         with:
//           context: .
//           push: ${{ steps.mode.outputs.push == 'true' }}
//           platforms: linux/amd64,linux/arm64
//           tags: ${{ steps.meta.outputs.tags }}
//           labels: ${{ steps.meta.outputs.labels }}
//           cache-from: type=gha
//           cache-to: type=gha,mode=max
//
//   docker-android:
//     name: Android builder image
//     runs-on: ubuntu-latest
//     # Serialised behind the web image on purpose. Both jobs start a BuildKit
//     # container, and an anonymous Docker Hub pull is rate limited per source
//     # address — two at once on the same runner pool is what produced
//     # "unauthorized: authentication required" from Set up Buildx. Running them
//     # in sequence costs wall-clock time and buys back a whole class of failure.
//     needs: docker
//     timeout-minutes: 40
//     permissions:
//       contents: read
//       packages: write
//     steps:
//       - name: Check out repository
//         uses: actions/checkout@v4
//
//       - name: Set up Buildx
//         uses: docker/setup-buildx-action@v3
//
//       - name: Decide whether this run publishes
//         id: mode
//         run: |
//           if [ "${{ github.event_name }}" = "pull_request" ]; then
//             echo "push=false" >> "$GITHUB_OUTPUT"
//             echo "Pull request: building only, not publishing."
//           else
//             echo "push=true" >> "$GITHUB_OUTPUT"
//             echo "Branch build: publishing to GHCR."
//           fi
//
//       - name: Collect tags and labels
//         id: meta
//         uses: docker/metadata-action@v5
//         with:
//           images: ghcr.io/${{ github.repository_owner }}/2048-game-android
//           tags: |
//             type=ref,event=branch
//             type=ref,event=pr
//             type=sha,format=long
//             type=raw,value=latest,enable={{is_default_branch}}
//
//       # linux/amd64 only. Google ships the Android command-line tools and
//       # build-tools for Linux as x86_64 binaries, so an arm64 image would build
//       # cleanly and then fail at aapt2 and d8.
//       - name: Build the SDK image
//         uses: docker/build-push-action@v6
//         with:
//           context: .
//           file: Dockerfile.android
//           target: sdk
//           push: false
//           load: true
//           platforms: linux/amd64
//           tags: 2048-android-sdk:${{ github.sha }}
//           cache-from: type=gha,scope=android
//           cache-to: type=gha,mode=max,scope=android
//
//       # An image that builds while missing a toolchain fails later and further
//       # from the cause. `bash -lc` is deliberate: a login shell resets PATH, so
//       # this also proves the /usr/local/bin symlinks are doing their job.
//       - name: Verify the toolchain inside the image
//         run: |
//           set -Eeuo pipefail
//           image="2048-android-sdk:${{ github.sha }}"
//           echo "--- Adoptium JDK 17, matching gradle-daemon-jvm.properties ---"
//           docker run --rm "$image" bash -lc 'java -version 2>&1 | head -1 | grep -q "17\."'
//           echo "--- the SDK entry points must resolve in a login shell ---"
//           docker run --rm "$image" bash -lc 'adb --version >/dev/null && sdkmanager --version >/dev/null'
//           echo "--- compileSdk 34 and its build-tools must be installed ---"
//           docker run --rm "$image" bash -lc 'test -d "$ANDROID_HOME/platforms/android-34"'
//           docker run --rm "$image" bash -lc 'test -d "$ANDROID_HOME/build-tools/34.0.0"'
//           echo "Toolchain verified."
//
//       # Proves the published image can actually build this project, not merely
//       # that the binaries exist. Runs the unit tests too, so a broken build
//       # cannot yield a green image. The APK lands on the runner via --output,
//       # with no container started and nothing published.
//       - name: Build the debug APK from the image
//         uses: docker/build-push-action@v6
//         with:
//           context: .
//           file: Dockerfile.android
//           target: apk
//           platforms: linux/amd64
//           outputs: type=local,dest=android-apk
//           cache-from: type=gha,scope=android
//           cache-to: type=gha,mode=max,scope=android
//
//       - name: Confirm the APK is real
//         run: |
//           set -Eeuo pipefail
//           ls -la android-apk/
//           test -s android-apk/app-debug.apk
//           # An APK is a zip; a truncated or placeholder file is not.
//           unzip -l android-apk/app-debug.apk | grep -q AndroidManifest.xml
//           echo "APK verified: $(du -h android-apk/app-debug.apk | cut -f1)"
//
//       - name: Upload the containerized debug APK
//         uses: actions/upload-artifact@v4
//         with:
//           name: android-debug-apk-container-built
//           path: android-apk/app-debug.apk
//           if-no-files-found: error
//
//       - name: Log in to GHCR
//         if: steps.mode.outputs.push == 'true'
//         uses: docker/login-action@v3
//         with:
//           registry: ghcr.io
//           username: ${{ github.actor }}
//           password: ${{ secrets.GITHUB_TOKEN }}
//
//       - name: Publish the SDK image
//         if: steps.mode.outputs.push == 'true'
//         uses: docker/build-push-action@v6
//         with:
//           context: .
//           file: Dockerfile.android
//           target: sdk
//           push: true
//           platforms: linux/amd64
//           tags: ${{ steps.meta.outputs.tags }}
//           labels: ${{ steps.meta.outputs.labels }}
//           cache-from: type=gha,scope=android

// SOURCE: .pre-commit-config.yaml

// minimum_pre_commit_version: "3.7.0"
// default_install_hook_types: [pre-commit, pre-push]
//
// repos:
//   - repo: https://github.com/pre-commit/pre-commit-hooks
//     rev: v5.0.0
//     hooks:
//       - id: check-case-conflict
//       - id: check-json
//       - id: check-merge-conflict
//       - id: check-symlinks
//       - id: check-yaml
//       - id: detect-private-key
//       - id: end-of-file-fixer
//         exclude: "(\\.png|\\.ico|\\.jar)$"
//       - id: mixed-line-ending
//         args: [--fix=lf]
//         exclude: "\\.bat$"
//       - id: trailing-whitespace
//         exclude: "\\.md$"
//
//   - repo: local
//     hooks:
//       - id: repository-check
//         name: repository structure and source checks
//         entry: ./scripts/check-repo.sh --staged
//         language: system
//         pass_filenames: false
//         stages: [pre-commit]
//       - id: project-tests
//         name: complete web test suite
//         entry: ./scripts/test-web.sh
//         language: system
//         pass_filenames: false
//         stages: [pre-push]
