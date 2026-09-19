import XCTest
@testable import Game_2048

/// The account surface's state machine.
@MainActor
final class CloudControllerTests: XCTestCase {
    private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
        let routes: [String: (Int, String)]
        var calls: [String] = []
        var failWith: CloudError?

        init(_ routes: [String: (Int, String)]) { self.routes = routes }

        func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (Int, Data) {
            let path = url.path
            calls.append("\(method) \(path)")
            if let failWith { throw failWith }
            let response = routes[path] ?? (200, "{}")
            return (response.0, Data(response.1.utf8))
        }
    }

    private let board = [512, 256, 128, 64, 32, 16, 8, 4, 2, 0, 0, 0, 0, 0, 0, 0]
    private func save(score: Int = 5600) -> CloudSave {
        CloudSave(board: board, score: score, bestScore: score, won: false, gameOver: false, moves: 400)
    }

    private let sessionBody = """
        {"user":{"id":"u1","username":"ada","displayName":"Ada","email":"ada@example.test","statistics":{"bestScore":900,"gamesPlayed":12,"highestTile":256}},
         "accessToken":"a","refreshToken":"r"}
        """

    private func makeController(
        transport: ScriptedTransport,
        tokens: CloudTokens? = nil,
        promptDismissed: Bool = false
    ) -> (CloudController, UserDefaultsCloudStore) {
        let suite = "CloudControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = UserDefaultsCloudStore(defaults: defaults)
        store.promptDismissed = promptDismissed
        if let tokens { store.write(tokens) }
        // Same store for tokens and the guest-prompt flag — matches production.
        let api = CloudAPI(transport: transport, tokens: store, baseURL: URL(string: "https://api.test")!)
        return (CloudController(api: api, store: store), store)
    }

    func testFreshControllerIsSignedOutAndInvitesPlayer() {
        let (controller, _) = makeController(transport: ScriptedTransport([:]))

        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertFalse(controller.isSignedIn)
        XCTAssertTrue(controller.showGuestPrompt, "an account is offered, never required")
        XCTAssertTrue(controller.status.contains("saved locally"))
    }

    func testDismissingInvitationHidesItAndRemembersChoice() {
        let (controller, store) = makeController(transport: ScriptedTransport([:]))

        controller.dismissPrompt()

        XCTAssertFalse(controller.showGuestPrompt)
        XCTAssertTrue(store.promptDismissed)
    }

    func testAlreadyDismissedInvitationStaysDismissed() {
        let (controller, _) = makeController(transport: ScriptedTransport([:]), promptDismissed: true)
        XCTAssertFalse(controller.showGuestPrompt)
    }

    func testRegisteringSignsInAndReconcilesImmediately() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/register": (201, sessionBody),
            "/api/v1/saves/sync": (200, #"{"resolution":"uploaded","save":null}"#)
        ])
        let (controller, _) = makeController(transport: transport)
        var applied: [CloudSave] = []

        await controller.register(username: "ada", email: "ada@example.test", password: "Password1", save: { self.save() }, apply: { applied.append($0) })

        XCTAssertEqual(controller.phase, .signedIn)
        XCTAssertEqual(controller.user?.displayName, "Ada")
        XCTAssertFalse(controller.showGuestPrompt, "signing in dismisses the invitation")
        XCTAssertEqual(controller.lastResolution, .uploaded)
        XCTAssertEqual(controller.status, "Round saved to your account.")
        XCTAssertEqual(transport.calls, ["POST /api/v1/auth/register", "POST /api/v1/saves/sync"])
        XCTAssertTrue(applied.isEmpty)
    }

    func testRejectedSignInReportsReasonAndStaysSignedOut() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (401, #"{"error":{"code":"invalid_credentials","message":"That email or password is not correct."}}"#)
        ])
        let (controller, _) = makeController(transport: transport)

        await controller.login(identifier: "ada", password: "wrong", save: { self.save() }, apply: { _ in })

        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertNil(controller.user)
        XCTAssertNotNil(controller.authError)
        XCTAssertTrue(controller.authError?.contains("not correct") == true)
    }

    func testClearingAuthErrorResetsTheForm() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (401, #"{"error":{"code":"x","message":"nope"}}"#)
        ])
        let (controller, _) = makeController(transport: transport)

        await controller.login(identifier: "ada", password: "wrong", save: { self.save() }, apply: { _ in })
        controller.clearAuthError()

        XCTAssertNil(controller.authError)
    }

    func testDownloadedRoundReplacesBoardAndUploadDoesNot() async {
        let remote = #"{"resolution":"downloaded","save":{"board":[2,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":40,"moves":3}}"#
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/saves/sync": (200, remote)
        ])
        let (controller, _) = makeController(transport: transport)
        var applied: [CloudSave] = []

        await controller.login(identifier: "ada", password: "Password1", save: { self.save() }, apply: { applied.append($0) })

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied[0].score, 40)
        XCTAssertEqual(controller.lastResolution, .downloaded)
        XCTAssertEqual(controller.status, "Restored the round from your account.")
    }

    func testRestoreWithTokensFetchesProfileAndSyncs() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/me": (200, #"{"user":{"id":"u1","username":"ada","displayName":"Ada","email":"ada@example.test","statistics":{}}}"#),
            "/api/v1/saves/sync": (200, #"{"resolution":"in_sync","save":null}"#)
        ])
        let (controller, _) = makeController(
            transport: transport,
            tokens: CloudTokens(accessToken: "a", refreshToken: "r")
        )

        await controller.restore(save: { self.save() }, apply: { _ in })

        XCTAssertEqual(controller.phase, .signedIn)
        XCTAssertEqual(controller.user?.displayName, "Ada")
        XCTAssertEqual(controller.lastResolution, .inSync)
        XCTAssertEqual(transport.calls, ["GET /api/v1/auth/me", "POST /api/v1/saves/sync"])
    }

    func testRestoreWithoutTokensIsANoOp() async {
        let transport = ScriptedTransport([:])
        let (controller, _) = makeController(transport: transport)

        await controller.restore(save: { self.save() }, apply: { _ in })

        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testNetworkFailureDuringRestoreKeepsTokensAndReassures() async {
        let transport = ScriptedTransport([:])
        transport.failWith = .network
        let (controller, store) = makeController(
            transport: transport,
            tokens: CloudTokens(accessToken: "a", refreshToken: "r")
        )

        await controller.restore(save: { self.save() }, apply: { _ in })

        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertTrue(store.hasTokens)
        XCTAssertTrue(controller.status.contains("Offline"))
    }

    func testSignOutClearsSessionAndKeepsLocalRoundMessage() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/saves/sync": (200, #"{"resolution":"uploaded","save":null}"#),
            "/api/v1/auth/logout": (200, "{}")
        ])
        let (controller, store) = makeController(transport: transport)

        await controller.login(identifier: "ada", password: "Password1", save: { self.save() }, apply: { _ in })
        await controller.signOut()

        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertNil(controller.user)
        XCTAssertNil(store.read())
        XCTAssertTrue(controller.status.contains("stays on this device"))
    }

    func testSubmitRoundSkipsWhenSignedOutOrZeroScore() async {
        let transport = ScriptedTransport([:])
        let (controller, _) = makeController(transport: transport)

        await controller.submitRound(save(score: 100))
        XCTAssertTrue(transport.calls.isEmpty)

        // Sign in via direct state path: login then submit zero.
        let signedIn = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/saves/sync": (200, #"{"resolution":"in_sync"}"#)
        ])
        let (active, _) = makeController(transport: signedIn)
        await active.login(identifier: "ada", password: "x", save: { self.save() }, apply: { _ in })
        await active.submitRound(save(score: 0))
        XCTAssertFalse(signedIn.calls.contains("POST /api/v1/scores"))
    }

    func testLoadLeaderboardUpdatesEntriesAndNote() async {
        let transport = ScriptedTransport([
            "/api/v1/leaderboard": (200, #"{"entries":[{"rank":1,"username":"ada","displayName":"Ada","score":900,"highestTile":256}],"summary":{"players":3,"topScore":900}}"#)
        ])
        let (controller, _) = makeController(transport: transport)

        await controller.loadLeaderboard(period: "weekly")

        XCTAssertEqual(controller.leaderboardPeriod, "weekly")
        XCTAssertEqual(controller.leaderboard?.entries.count, 1)
        XCTAssertTrue(controller.leaderboardNote.contains("3 players"))
    }

    func testConflictedSyncDescribesPreservation() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/saves/sync": (200, #"{"resolution":"conflicted","conflictSlot":"c1","winner":"local"}"#)
        ])
        let (controller, _) = makeController(transport: transport)

        await controller.login(identifier: "ada", password: "Password1", save: { self.save() }, apply: { _ in })

        XCTAssertEqual(controller.lastResolution, .conflicted)
        XCTAssertTrue(controller.status.contains("further one was kept"))
    }

    func testEmptyLeaderboardNoteInvitesFirstScore() async {
        let transport = ScriptedTransport([
            "/api/v1/leaderboard": (200, #"{"entries":[],"summary":{"players":0,"topScore":0}}"#)
        ])
        let (controller, _) = makeController(transport: transport)

        await controller.loadLeaderboard()

        XCTAssertTrue(controller.leaderboardNote.contains("first"))
    }

    func testLeaderboardNetworkFailureSurfacesMessage() async {
        let transport = ScriptedTransport([:])
        transport.failWith = .network
        let (controller, _) = makeController(transport: transport)

        await controller.loadLeaderboard()

        XCTAssertNil(controller.leaderboard)
        XCTAssertTrue(controller.leaderboardNote.contains("still saved"))
    }

    // MARK: - ViewModel bridge

    func testCloudSaveFlattensBoardAndApplyRestoresIt() {
        let suite = "CloudBridge-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let game = GameViewModel(loadSavedGame: false, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
        game.setGameForTesting(grid: [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], score: 40)
        XCTAssertTrue(game.swipe(direction: .left))

        let payload = game.cloudSave()
        XCTAssertEqual(payload.board.count, 16)
        XCTAssertEqual(payload.score, game.score)
        XCTAssertGreaterThan(payload.moves, 0)

        let other = GameViewModel(loadSavedGame: false, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
        XCTAssertTrue(other.applyCloudSave(payload))
        XCTAssertEqual(other.grid, game.grid)
        XCTAssertEqual(other.score, game.score)
        XCTAssertEqual(other.moves, payload.moves)
        XCTAssertFalse(other.canUndo)
    }

    func testApplyCloudSaveRejectsCorruptBoard() {
        let suite = "CloudBridgeBad-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let game = GameViewModel(loadSavedGame: false, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
        let before = game.grid

        XCTAssertFalse(game.applyCloudSave(CloudSave(board: [1, 2, 3], score: 10, bestScore: 10, won: false, gameOver: false, moves: 1)))
        XCTAssertEqual(game.grid, before)
    }

    func testMovesSurviveUndoAndFeedCloudSave() {
        let suite = "CloudBridgeMoves-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let game = GameViewModel(loadSavedGame: false, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
        game.setGameForTesting(grid: [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertTrue(game.swipe(direction: .left))
        let movesAfter = game.moves
        game.undo()
        XCTAssertEqual(game.moves, movesAfter, "moves must not rewind — they measure progress for sync")
        XCTAssertEqual(game.cloudSave().moves, movesAfter)
    }
}
