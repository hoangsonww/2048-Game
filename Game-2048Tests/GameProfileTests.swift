import XCTest
import AVFoundation
@testable import Game_2048

/// Guest and account profiles, and the cue mixer.
///
/// The property under test is separation: two rounds live on one device and
/// neither can reach the other. Signing in must not hand a guest board to an
/// account, and signing out must return the guest board untouched.
@MainActor
final class GameProfileTests: XCTestCase {
    private func makeDefaults(_ label: String = #function) -> UserDefaults {
        let suite = "GameProfileTests-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeGame(_ defaults: UserDefaults) -> GameViewModel {
        GameViewModel(defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
    }

    /// Plays until the round has a score worth protecting.
    @discardableResult
    private func playUntilScored(_ game: GameViewModel) -> (grid: [[Int]], score: Int, best: Int, moves: Int) {
        game.setGameForTesting(grid: [[2, 2, 0, 0], [4, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertGreaterThan(game.score, 0)
        return (game.grid, game.score, game.highScore, game.moves)
    }

    func testARoundStartsOnTheGuestProfile() {
        let game = makeGame(makeDefaults())
        XCTAssertEqual(game.profile, .guest)
        XCTAssertFalse(game.hasProgress)
    }

    func testProgressIsAnythingAPlayerWouldMindLosing() {
        let game = makeGame(makeDefaults())
        game.setGameForTesting(grid: [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertFalse(game.hasProgress)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertTrue(game.hasProgress)
    }

    func testStartingAnAccountSessionParksTheGuestRoundUntouched() {
        let defaults = makeDefaults()
        let game = makeGame(defaults)
        let guest = playUntilScored(game)

        XCTAssertEqual(game.beginAccountSession(fresh: true), .fresh)

        XCTAssertEqual(game.profile, .account)
        XCTAssertEqual(game.score, 0, "the account starts on a clean board")
        XCTAssertEqual(game.highScore, 0, "and with no best score borrowed from the device")
        XCTAssertEqual(defaults.array(forKey: "savedGridV2") as? [Int], guest.grid.flatMap { $0 })
        XCTAssertEqual(defaults.integer(forKey: "savedScoreV2"), guest.score)
        XCTAssertEqual(defaults.integer(forKey: "highScore"), guest.best)
    }

    func testPlayingSignedInNeverWritesToTheGuestProfile() {
        let defaults = makeDefaults()
        let game = makeGame(defaults)
        let guest = playUntilScored(game)

        game.beginAccountSession(fresh: true)
        game.setGameForTesting(grid: [[8, 8, 0, 0], [16, 16, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertTrue(game.swipe(direction: .left))

        XCTAssertEqual(defaults.array(forKey: "savedGridV2") as? [Int], guest.grid.flatMap { $0 })
        XCTAssertEqual(defaults.integer(forKey: "savedScoreV2"), guest.score)
        XCTAssertEqual(defaults.integer(forKey: "highScore"), guest.best)
        XCTAssertNotNil(defaults.array(forKey: "accountSavedGridV1"))
        XCTAssertEqual(defaults.integer(forKey: "accountHighScoreV1"), game.highScore)
    }

    func testEndingAnAccountSessionRestoresTheGuestRoundExactly() {
        let defaults = makeDefaults()
        let game = makeGame(defaults)
        let guest = playUntilScored(game)

        game.beginAccountSession(fresh: true)
        game.setGameForTesting(grid: [[8, 8, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertNotEqual(game.grid, guest.grid)

        XCTAssertTrue(game.endAccountSession())

        XCTAssertEqual(game.profile, .guest)
        XCTAssertEqual(game.grid, guest.grid)
        XCTAssertEqual(game.score, guest.score)
        XCTAssertEqual(game.highScore, guest.best)
        XCTAssertEqual(game.moves, guest.moves)
        XCTAssertNil(defaults.array(forKey: "accountSavedGridV1"), "the cached account round does not outlive the session")
    }

    func testASessionStartedTwiceIsReportedAsAlreadyActive() {
        let game = makeGame(makeDefaults())
        XCTAssertEqual(game.beginAccountSession(fresh: true), .fresh)
        XCTAssertEqual(game.beginAccountSession(), .active)
        XCTAssertEqual(game.profile, .account)
    }

    func testEndingASessionThatNeverStartedChangesNothing() {
        let game = makeGame(makeDefaults())
        let before = game.grid
        XCTAssertFalse(game.endAccountSession())
        XCTAssertEqual(game.grid, before)
        XCTAssertEqual(game.profile, .guest)
    }

    func testACachedAccountRoundIsRestoredRatherThanReplaced() {
        let defaults = makeDefaults()
        defaults.set([512, 256, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], forKey: "accountSavedGridV1")
        defaults.set(4000, forKey: "accountSavedScoreV1")
        defaults.set(6000, forKey: "accountHighScoreV1")
        defaults.set(77, forKey: "accountSavedMovesV1")
        let game = makeGame(defaults)

        XCTAssertEqual(game.beginAccountSession(), .restored)

        XCTAssertEqual(game.score, 4000)
        XCTAssertEqual(game.highScore, 6000)
        XCTAssertEqual(game.moves, 77)
    }

    func testAFreshSignInDiscardsWhateverWasCachedForAnAccount() {
        let defaults = makeDefaults()
        defaults.set([512, 256, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], forKey: "accountSavedGridV1")
        defaults.set(4000, forKey: "accountSavedScoreV1")
        let game = makeGame(defaults)

        XCTAssertEqual(game.beginAccountSession(fresh: true), .fresh)

        XCTAssertEqual(game.score, 0, "the previous occupant's board is not this account's")
    }

    func testAProfileSwitchIsAnnouncedSeparatelyFromANewGame() {
        let game = makeGame(makeDefaults())
        var changes: [GameViewModel.RoundChange] = []
        game.onRoundChanged = { changes.append($0) }

        game.beginAccountSession(fresh: true)
        game.endAccountSession()

        XCTAssertEqual(changes, [.profileChanged, .profileChanged])
    }

    func testABestScoreEarnedSignedInStaysWithTheAccount() {
        let defaults = makeDefaults()
        let game = makeGame(defaults)
        playUntilScored(game)
        let guestBest = game.highScore

        game.beginAccountSession(fresh: true)
        game.setGameForTesting(grid: [[512, 512, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertGreaterThan(game.highScore, guestBest)

        game.endAccountSession()
        XCTAssertEqual(game.highScore, guestBest, "a signed-in score is not the device's own best")
    }

    // MARK: - Cue synthesis

    func testEveryCueRendersAShapedBurstOfTheRightLength() {
        let tone = GameSounds.Tone(frequency: 440, duration: 0.05, volume: 0.2, slideTo: nil)
        let samples = GameSounds.render(tone, sampleRate: 44_100)

        XCTAssertEqual(samples.count, Int(0.05 * 44_100))
        XCTAssertEqual(samples.first ?? 1, 0, accuracy: 0.0001, "a cue fades in rather than clicking")
        XCTAssertTrue(samples.allSatisfy { abs($0) <= 1 }, "nothing clips")
        XCTAssertTrue(samples.contains { abs($0) > 0.01 }, "and something is actually audible")
    }

    func testASlidingCueChangesPitchAcrossItsLength() {
        let flat = GameSounds.render(
            GameSounds.Tone(frequency: 300, duration: 0.1, volume: 0.3, slideTo: nil),
            sampleRate: 8_000
        )
        let sliding = GameSounds.render(
            GameSounds.Tone(frequency: 300, duration: 0.1, volume: 0.3, slideTo: 120),
            sampleRate: 8_000
        )

        XCTAssertEqual(flat.count, sliding.count)
        XCTAssertNotEqual(flat.suffix(50), sliding.suffix(50))
    }

    func testAZeroLengthCueStillProducesAValidBuffer() {
        let samples = GameSounds.render(
            GameSounds.Tone(frequency: 200, duration: 0, volume: 0.1, slideTo: nil),
            sampleRate: 44_100
        )
        XCTAssertEqual(samples.count, 1, "a degenerate cue is one silent frame, never a crash")
    }

    func testTheCueMixerHasRoomForOverlappingVoices() {
        // A single player node is a queue: cues scheduled on it play strictly
        // one after another, which is what turned a fast run of moves into a
        // backlog draining seconds later.
        XCTAssertGreaterThan(GameSounds.voiceCount, 1)
    }

    func testMutingIsRememberedAndCuesAreSilentWhileMuted() {
        let defaults = makeDefaults()
        let sounds = GameSounds(defaults: defaults)
        XCTAssertTrue(sounds.isEnabled)

        sounds.toggle()
        XCTAssertFalse(sounds.isEnabled)
        XCTAssertFalse(GameSounds(defaults: defaults).isEnabled)

        // Every cue is safe to call while muted; none of them should throw or
        // reach the engine.
        sounds.move()
        sounds.merge(points: 64)
        sounds.undo()
        sounds.newGame()
        sounds.win()
        sounds.gameOver()
        sounds.invalid()

        sounds.toggle()
        XCTAssertTrue(sounds.isEnabled)
    }
}
