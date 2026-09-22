import XCTest
@testable import Game_2048

/// The account surface's state machine.
@MainActor
final class CloudControllerTests: XCTestCase {
    private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
        let routes: [String: (Int, String)]
        var calls: [String] = []
        var failWith: CloudError?
        /// Anything that is *not* a `CloudError` — a bug rather than a
        /// network problem. The controller still has to say something a
        /// player can read.
        var failWithUnexpected: Error?
        var latch: Latch?

        init(_ routes: [String: (Int, String)]) { self.routes = routes }

        func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (Int, Data) {
            let path = url.path
            calls.append("\(method) \(path)")
            await latch?.wait()
            if let failWithUnexpected { throw failWithUnexpected }
            if let failWith { throw failWith }
            let response = routes[path] ?? (200, "{}")
            return (response.0, Data(response.1.utf8))
        }
    }

    private final class Latch: @unchecked Sendable {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
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
        XCTAssertEqual(controller.activity, .idle)
        XCTAssertFalse(controller.isBusy)
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

    func testRegisteringSignsInWithoutTouchingTheNetworkAgain() async {
        let transport = ScriptedTransport(["/api/v1/auth/register": (201, sessionBody)])
        let (controller, _) = makeController(transport: transport)

        let succeeded = await controller.register(username: "ada", email: "ada@example.test", password: "Password1")

        XCTAssertTrue(succeeded)
        XCTAssertEqual(controller.phase, .signedIn)
        XCTAssertEqual(controller.activity, .idle)
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(controller.user?.displayName, "Ada")
        XCTAssertFalse(controller.showGuestPrompt, "signing in dismisses the invitation")
        // Authentication no longer decides what happens to the round. The
        // game does, because only the game knows which profile is now active.
        XCTAssertEqual(transport.calls, ["POST /api/v1/auth/register"])
    }

    func testAdoptingAnAccountOffersTheServerNothing() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/register": (201, sessionBody),
            "/api/v1/saves/sync": (200, #"{"resolution":"in_sync","save":null}"#),
            "/api/v1/auth/me": (200, #"{"user":{"id":"u1","username":"ada","displayName":"Ada","email":"ada@example.test","statistics":{"bestScore":0,"gamesPlayed":0,"highestTile":0}}}"#)
        ])
        let (controller, _) = makeController(transport: transport)
        var applied: [CloudSave] = []

        _ = await controller.register(username: "ada", email: "ada@example.test", password: "Password1")
        await controller.adoptAccountRound(apply: { applied.append($0) })

        XCTAssertEqual(controller.lastResolution, .inSync)
        XCTAssertEqual(controller.status, "Signed in. Your account is ready.")
        XCTAssertTrue(applied.isEmpty, "an account with no round leaves the clean board alone")
        XCTAssertEqual(
            transport.calls,
            ["POST /api/v1/auth/register", "POST /api/v1/saves/sync", "GET /api/v1/auth/me"]
        )
    }

    func testAdoptingAnAccountReportsAFailureRatherThanClaimingSuccess() async {
        let transport = ScriptedTransport(["/api/v1/auth/register": (201, sessionBody)])
        let (controller, _) = makeController(transport: transport)
        _ = await controller.register(username: "ada", email: "ada@example.test", password: "Password1")
        transport.failWith = .network

        await controller.adoptAccountRound(apply: { _ in })

        XCTAssertTrue(controller.status.contains("still saved"))
        XCTAssertEqual(controller.activity, .idle)
    }

    func testSigningInDiscardsARevisionFromAnEarlierSession() async {
        let transport = ScriptedTransport(["/api/v1/auth/login": (200, sessionBody)])
        let (controller, store) = makeController(transport: transport)
        store.knownRevision = 12

        _ = await controller.login(identifier: "ada", password: "Password1")

        XCTAssertNil(store.knownRevision, "a stale revision would make the next upload claim a false ancestry")
    }

    func testCareerTotalsAreNeverLiftedFromTheLocalRound() async {
        // The bug this guards: a brand-new account advertising a best score and
        // a highest tile taken from whatever board happened to be on the device.
        let emptyStats = """
            {"user":{"id":"u1","username":"ada","displayName":"Ada","email":"ada@example.test","statistics":{"bestScore":0,"gamesPlayed":0,"highestTile":0}},
             "accessToken":"a","refreshToken":"r"}
            """
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, emptyStats),
            "/api/v1/saves/sync": (200, #"{"resolution":"uploaded","save":{"board":[512,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":5600,"bestScore":5600,"revision":1}}"#)
        ])
        let (controller, _) = makeController(transport: transport)

        _ = await controller.login(identifier: "ada", password: "Password1")
        await controller.sync(save: { self.save() }, apply: { _ in })

        XCTAssertEqual(controller.user?.statistics.bestScore, 0)
        XCTAssertEqual(controller.user?.statistics.gamesPlayed, 0)
        XCTAssertEqual(controller.user?.statistics.highestTile, 0)
    }

    func testRejectedSignInReportsReasonAndStaysSignedOut() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (401, #"{"error":{"code":"invalid_credentials","message":"That email or password is not correct."}}"#)
        ])
        let (controller, _) = makeController(transport: transport)

        await controller.login(identifier: "ada", password: "wrong")

        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertEqual(controller.activity, .idle)
        XCTAssertNil(controller.user)
        XCTAssertNotNil(controller.authError)
        XCTAssertTrue(controller.authError?.contains("not correct") == true)
    }

    func testInFlightAuthPublishesABusyActivityUntilTheRequestFinishes() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/saves/sync": (200, #"{"resolution":"uploaded","save":null}"#)
        ])
        transport.latch = Latch()
        let (controller, _) = makeController(transport: transport)

        let task = Task {
            await controller.login(identifier: "ada", password: "Password1")
        }
        var spins = 0
        while controller.activity != .authenticating && spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertEqual(controller.activity, .authenticating)
        XCTAssertTrue(controller.isBusy)
        XCTAssertTrue(controller.status.contains("Signing in"))

        transport.latch?.open()
        await task.value

        XCTAssertEqual(controller.activity, .idle)
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(controller.phase, .signedIn)
    }

    func testInFlightSyncAndLeaderboardPublishBusyActivities() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/saves/sync": (200, #"{"resolution":"uploaded","save":null}"#),
            "/api/v1/leaderboard": (200, #"{"entries":[],"summary":{"players":0,"topScore":0}}"#)
        ])
        let (controller, _) = makeController(transport: transport)
        await controller.login(identifier: "ada", password: "Password1")

        transport.latch = Latch()
        let sync = Task { await controller.syncNow(save: { self.save() }, apply: { _ in }) }
        var spins = 0
        while controller.activity != .syncing && spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertEqual(controller.activity, .syncing)
        XCTAssertTrue(controller.status.contains("Syncing"))
        transport.latch?.open()
        await sync.value
        XCTAssertEqual(controller.activity, .idle)

        transport.latch = Latch()
        let board = Task { await controller.loadLeaderboard() }
        spins = 0
        while controller.activity != .loadingLeaderboard && spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertEqual(controller.activity, .loadingLeaderboard)
        XCTAssertEqual(controller.leaderboardNote, "Loading…")
        transport.latch?.open()
        await board.value
        XCTAssertEqual(controller.activity, .idle)
    }

    func testClearingAuthErrorResetsTheForm() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (401, #"{"error":{"code":"x","message":"nope"}}"#)
        ])
        let (controller, _) = makeController(transport: transport)

        await controller.login(identifier: "ada", password: "wrong")
        controller.clearAuthError()

        XCTAssertNil(controller.authError)
    }

    func testSyncNowPrefersLocalAndRemembersRevision() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/saves/sync": (200, #"{"resolution":"uploaded","save":{"board":[2],"score":1,"revision":5}}"#),
            "/api/v1/auth/me": (200, #"{"user":{"id":"u1","username":"ada","displayName":"Ada","email":"ada@example.test","statistics":{"bestScore":5600,"gamesPlayed":12,"highestTile":512}}}"#)
        ])
        let (controller, store) = makeController(transport: transport)

        await controller.login(identifier: "ada", password: "Password1")
        transport.calls.removeAll()

        await controller.syncNow(save: { self.save() }, apply: { _ in })

        XCTAssertEqual(store.knownRevision, 5)
        XCTAssertEqual(controller.user?.statistics.bestScore, 5600)
        XCTAssertTrue(transport.calls.contains("POST /api/v1/saves/sync"))
        XCTAssertTrue(transport.calls.contains("GET /api/v1/auth/me"))
    }

    func testRemoteWinningConflictReplacesBoard() async {
        let remote = #"{"resolution":"conflicted","winner":"remote","save":{"board":[2,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":40,"moves":3,"revision":2}}"#
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/saves/sync": (200, remote)
        ])
        let (controller, store) = makeController(transport: transport)
        var applied: [CloudSave] = []

        _ = await controller.login(identifier: "ada", password: "Password1")
        await controller.sync(save: { self.save() }, apply: { applied.append($0) })

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied[0].score, 40)
        XCTAssertEqual(store.knownRevision, 2)
    }

    func testSignOutClearsKnownRevision() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/saves/sync": (200, #"{"resolution":"uploaded","save":{"revision":9}}"#),
            "/api/v1/auth/logout": (200, "{}")
        ])
        let (controller, store) = makeController(transport: transport)

        _ = await controller.login(identifier: "ada", password: "Password1")
        await controller.sync(save: { self.save() }, apply: { _ in })
        XCTAssertEqual(store.knownRevision, 9)

        await controller.signOut()

        XCTAssertNil(store.knownRevision)
    }

    func testDownloadedRoundReplacesBoardAndUploadDoesNot() async {
        let remote = #"{"resolution":"downloaded","save":{"board":[2,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":40,"moves":3}}"#
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/saves/sync": (200, remote)
        ])
        let (controller, _) = makeController(transport: transport)
        var applied: [CloudSave] = []

        _ = await controller.login(identifier: "ada", password: "Password1")
        await controller.adoptAccountRound(apply: { applied.append($0) })

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied[0].score, 40)
        XCTAssertEqual(controller.lastResolution, .downloaded)
        XCTAssertEqual(controller.status, "Restored the round from your account.")
    }

    func testRestoreWithTokensFetchesProfileAndLeavesReconcilingToTheCaller() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/me": (200, #"{"user":{"id":"u1","username":"ada","displayName":"Ada","email":"ada@example.test","statistics":{}}}"#)
        ])
        let (controller, _) = makeController(
            transport: transport,
            tokens: CloudTokens(accessToken: "a", refreshToken: "r")
        )
        XCTAssertTrue(controller.hasStoredSession)

        let restored = await controller.restore()

        XCTAssertTrue(restored)
        XCTAssertEqual(controller.phase, .signedIn)
        XCTAssertEqual(controller.user?.displayName, "Ada")
        // Which round may be offered depends on which profile the device
        // adopted, and only the game knows that.
        XCTAssertEqual(transport.calls, ["GET /api/v1/auth/me"])
    }

    func testRestoreWithoutTokensIsANoOp() async {
        let transport = ScriptedTransport([:])
        let (controller, _) = makeController(transport: transport)

        let restored = await controller.restore()

        XCTAssertFalse(restored)
        XCTAssertFalse(controller.hasStoredSession)
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

        let restored = await controller.restore()

        XCTAssertFalse(restored)
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

        await controller.login(identifier: "ada", password: "Password1")
        await controller.signOut()

        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertNil(controller.user)
        XCTAssertNil(store.read())
        XCTAssertTrue(controller.status.contains("own round is back"))
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
        await active.login(identifier: "ada", password: "x")
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

        _ = await controller.login(identifier: "ada", password: "Password1")
        await controller.sync(save: { self.save() }, apply: { _ in })

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

    // MARK: - Password reset

    func testResettingAPasswordEndsTheSessionThisDeviceHeld() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/auth/reset-password": (200, #"{"reset":true,"sessionsRevoked":3}"#)
        ])
        let (controller, store) = makeController(transport: transport)
        _ = await controller.login(identifier: "ada", password: "Password1")
        store.knownRevision = 4
        XCTAssertTrue(controller.isSignedIn)

        let reset = await controller.resetPassword(username: "ada", email: "ada@example.test", newPassword: "Recovered1")

        XCTAssertTrue(reset)
        // The server revoked every session, this one included.
        XCTAssertFalse(controller.isSignedIn)
        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertNil(store.read())
        XCTAssertNil(store.knownRevision)
        XCTAssertTrue(controller.status.contains("Sign in with your new password"))
        XCTAssertEqual(controller.activity, .idle)
    }

    func testARejectedResetIsReportedAndChangesNothing() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/auth/reset-password": (401, #"{"error":{"code":"invalid_credentials","message":"That username and email do not match an account."}}"#)
        ])
        let (controller, store) = makeController(transport: transport)
        _ = await controller.login(identifier: "ada", password: "Password1")

        let reset = await controller.resetPassword(username: "ada", email: "wrong@example.test", newPassword: "Recovered1")

        XCTAssertFalse(reset)
        XCTAssertTrue(controller.authError?.contains("do not match an account") == true)
        XCTAssertTrue(controller.isSignedIn, "a refused reset must not sign anybody out")
        XCTAssertEqual(controller.phase, .signedIn)
        XCTAssertNotNil(store.read())
        XCTAssertEqual(controller.activity, .idle)
    }

    func testAResetWorksWithoutASessionToBeginWith() async {
        // The player who needs this is the one who cannot sign in.
        let transport = ScriptedTransport(["/api/v1/auth/reset-password": (200, #"{"reset":true,"sessionsRevoked":0}"#)])
        let (controller, _) = makeController(transport: transport)

        let reset = await controller.resetPassword(username: "ada", email: "ada@example.test", newPassword: "Recovered1")

        XCTAssertTrue(reset)
        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertEqual(transport.calls, ["POST /api/v1/auth/reset-password"])
    }

    // MARK: - Unexpected failures

    /// A bug is not a network problem, and the player still needs a sentence.
    private struct Bug: Error, LocalizedError {
        var errorDescription: String? { "a bug, not a network problem" }
    }

    func testAnUnexpectedFailureDuringSignInIsStillReadable() async {
        let transport = ScriptedTransport([:])
        transport.failWithUnexpected = Bug()
        let (controller, _) = makeController(transport: transport)

        let signedIn = await controller.login(identifier: "ada", password: "Password1")

        XCTAssertFalse(signedIn)
        XCTAssertEqual(controller.authError, "a bug, not a network problem")
        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertEqual(controller.activity, .idle)
    }

    func testAnUnexpectedFailureWhileAdoptingIsStillReadable() async {
        let transport = ScriptedTransport(["/api/v1/auth/login": (200, sessionBody)])
        let (controller, _) = makeController(transport: transport)
        _ = await controller.login(identifier: "ada", password: "Password1")
        transport.failWithUnexpected = Bug()

        await controller.adoptAccountRound(apply: { _ in })

        XCTAssertEqual(controller.status, "a bug, not a network problem")
        XCTAssertEqual(controller.activity, .idle)
    }

    func testAnUnexpectedFailureWhileResettingIsStillReadable() async {
        let transport = ScriptedTransport([:])
        transport.failWithUnexpected = Bug()
        let (controller, _) = makeController(transport: transport)

        let reset = await controller.resetPassword(username: "ada", email: "ada@example.test", newPassword: "Recovered1")

        XCTAssertFalse(reset)
        XCTAssertEqual(controller.authError, "a bug, not a network problem")
        XCTAssertEqual(controller.activity, .idle)
    }

    func testAnUnexpectedFailureWhileSyncingIsStillReadable() async {
        let transport = ScriptedTransport(["/api/v1/auth/login": (200, sessionBody)])
        let (controller, _) = makeController(transport: transport)
        _ = await controller.login(identifier: "ada", password: "Password1")
        transport.failWithUnexpected = Bug()

        await controller.sync(save: { self.save() }, apply: { _ in })

        XCTAssertEqual(controller.status, "a bug, not a network problem")
        XCTAssertTrue(controller.isSignedIn, "a failed sync is not a sign-out")
        XCTAssertEqual(controller.activity, .idle)
    }

    func testAnUnexpectedFailureLoadingTheLeaderboardIsStillReadable() async {
        let transport = ScriptedTransport([:])
        transport.failWithUnexpected = Bug()
        let (controller, _) = makeController(transport: transport)

        await controller.loadLeaderboard()

        XCTAssertNil(controller.leaderboard)
        XCTAssertEqual(controller.leaderboardNote, "a bug, not a network problem")
        XCTAssertEqual(controller.activity, .idle)
    }

    func testAnUnexpectedFailureDuringRestoreLeavesTheSessionAlone() async {
        let transport = ScriptedTransport([:])
        transport.failWithUnexpected = Bug()
        let (controller, store) = makeController(
            transport: transport,
            tokens: CloudTokens(accessToken: "a", refreshToken: "r")
        )

        let restored = await controller.restore()

        XCTAssertFalse(restored)
        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertTrue(store.hasTokens, "a bug must not throw away a session")
    }

    func testRestoringAgainstAProfileThatIsNotThereSignsOut() async {
        // A 200 with no user object is not a user; the launch simply does not
        // establish a session.
        let transport = ScriptedTransport(["/api/v1/auth/me": (200, "{}")])
        let (controller, _) = makeController(
            transport: transport,
            tokens: CloudTokens(accessToken: "a", refreshToken: "r")
        )

        let restored = await controller.restore()

        XCTAssertFalse(restored)
        XCTAssertFalse(controller.isSignedIn)
        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertEqual(controller.activity, .idle)
    }

    func testASubmittedRoundRefreshesTheAccountsCareerTotals() async {
        let transport = ScriptedTransport([
            "/api/v1/auth/login": (200, sessionBody),
            "/api/v1/scores": (201, #"{"statistics":{"bestScore":5600,"gamesPlayed":13,"highestTile":512}}"#),
            "/api/v1/auth/me": (200, #"{"user":{"id":"u1","username":"ada","displayName":"Ada","email":"a@b.test","statistics":{"bestScore":5600,"gamesPlayed":13,"highestTile":512}}}"#)
        ])
        let (controller, _) = makeController(transport: transport)
        _ = await controller.login(identifier: "ada", password: "Password1")

        await controller.submitRound(save(), durationSeconds: 90)

        XCTAssertTrue(transport.calls.contains("POST /api/v1/scores"))
        XCTAssertEqual(controller.user?.statistics.bestScore, 5600)
        XCTAssertEqual(controller.user?.statistics.gamesPlayed, 13)
        XCTAssertEqual(controller.activity, .idle)
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

// MARK: - Focused maintainer notes (documentation only)
//
// Cloud orchestration test maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Run controller assertions on the main actor to match production isolation.
//
// 02. Separate authentication, reconciliation, synchronization, leaderboard, and sign-out
//     scenarios.
//
// 03. Assert published activity while asynchronous work is suspended, not only after completion.
//
// 04. Keep guest and account rounds independent in every session transition test.
//
// 05. Verify career totals come from the account and are never copied from local round state.
//
// 06. Cover network, server, and unexpected errors with user-readable messages.
//
// 07. Use deterministic fake APIs so ordering and revision behavior remain reproducible.
//
// 08. Assert both state changes and the absence of forbidden state changes.
//
// Symbol and scenario index
//
// 01. `final class CloudControllerTests: XCTestCase`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `init(_ routes: [String: (Int, String)]) { self.routes = routes }`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 03. `func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (Int, Data)`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 04. `func wait() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 05. `func open()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 06. `private func save(score: Int = 5600) -> CloudSave`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 07. `private func makeController(`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 08. `func testFreshControllerIsSignedOutAndInvitesPlayer()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 09. `func testDismissingInvitationHidesItAndRemembersChoice()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 10. `func testAlreadyDismissedInvitationStaysDismissed()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 11. `func testRegisteringSignsInWithoutTouchingTheNetworkAgain() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 12. `func testAdoptingAnAccountOffersTheServerNothing() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 13. `func testAdoptingAnAccountReportsAFailureRatherThanClaimingSuccess() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 14. `func testSigningInDiscardsARevisionFromAnEarlierSession() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 15. `func testCareerTotalsAreNeverLiftedFromTheLocalRound() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 16. `func testRejectedSignInReportsReasonAndStaysSignedOut() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 17. `func testInFlightAuthPublishesABusyActivityUntilTheRequestFinishes() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 18. `func testInFlightSyncAndLeaderboardPublishBusyActivities() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 19. `func testClearingAuthErrorResetsTheForm() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 20. `func testSyncNowPrefersLocalAndRemembersRevision() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 21. `func testRemoteWinningConflictReplacesBoard() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 22. `func testSignOutClearsKnownRevision() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 23. `func testDownloadedRoundReplacesBoardAndUploadDoesNot() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 24. `func testRestoreWithTokensFetchesProfileAndLeavesReconcilingToTheCaller() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 25. `func testRestoreWithoutTokensIsANoOp() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 26. `func testNetworkFailureDuringRestoreKeepsTokensAndReassures() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 27. `func testSignOutClearsSessionAndKeepsLocalRoundMessage() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 28. `func testSubmitRoundSkipsWhenSignedOutOrZeroScore() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 29. `func testLoadLeaderboardUpdatesEntriesAndNote() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 30. `func testConflictedSyncDescribesPreservation() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 31. `func testEmptyLeaderboardNoteInvitesFirstScore() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 32. `func testLeaderboardNetworkFailureSurfacesMessage() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 33. `func testResettingAPasswordEndsTheSessionThisDeviceHeld() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 34. `func testARejectedResetIsReportedAndChangesNothing() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 35. `func testAResetWorksWithoutASessionToBeginWith() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 36. `func testAnUnexpectedFailureDuringSignInIsStillReadable() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 37. `func testAnUnexpectedFailureWhileAdoptingIsStillReadable() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 38. `func testAnUnexpectedFailureWhileResettingIsStillReadable() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 39. `func testAnUnexpectedFailureWhileSyncingIsStillReadable() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 40. `func testAnUnexpectedFailureLoadingTheLeaderboardIsStillReadable() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 41. `func testAnUnexpectedFailureDuringRestoreLeavesTheSessionAlone() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 42. `func testRestoringAgainstAProfileThatIsNotThereSignsOut() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 43. `func testASubmittedRoundRefreshesTheAccountsCareerTotals() async`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 44. `func testCloudSaveFlattensBoardAndApplyRestoresIt()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 45. `func testApplyCloudSaveRejectsCorruptBoard()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 46. `func testMovesSurviveUndoAndFeedCloudSave()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
