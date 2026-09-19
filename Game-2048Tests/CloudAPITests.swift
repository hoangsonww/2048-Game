import XCTest
@testable import Game_2048

/// The cloud client, driven through a fake transport.
///
/// The interesting cases are the ones a device makes hard to produce on
/// demand — an expired token, a dropped connection, a malformed response — so
/// they live here rather than in the UI suite.
final class CloudAPITests: XCTestCase {
    private struct Call {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data?
    }

    private final class FakeTransport: HTTPTransport, @unchecked Sendable {
        var calls: [Call] = []
        private var queue: [(Int, Data)]
        var throwNetworkError = false

        init(_ responses: [(Int, String)] = []) {
            queue = responses.map { ($0.0, Data($0.1.utf8)) }
        }

        func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (Int, Data) {
            calls.append(Call(method: method, url: url, headers: headers, body: body))
            if throwNetworkError { throw CloudError.network }
            guard queue.isEmpty == false else {
                fatalError("No queued response for \(method) \(url)")
            }
            return queue.removeFirst()
        }
    }

    private final class MemoryTokenStore: TokenStoring {
        private var tokens: CloudTokens?
        var writes = 0

        init(_ tokens: CloudTokens? = nil) { self.tokens = tokens }

        func read() -> CloudTokens? { tokens }

        func write(_ tokens: CloudTokens?) {
            self.tokens = tokens
            writes += 1
        }
    }

    private let sessionBody = """
        {
          "user": {
            "id": "u1",
            "username": "ada",
            "displayName": "Ada",
            "email": "ada@example.test",
            "statistics": { "bestScore": 900, "gamesPlayed": 12, "highestTile": 256 }
          },
          "accessToken": "access-1",
          "refreshToken": "refresh-1"
        }
        """

    private let board = [512, 256, 128, 64, 32, 16, 8, 4, 2, 0, 0, 0, 0, 0, 0, 0]

    private func save(score: Int = 5600, moves: Int = 480, baseRevision: Int? = nil) -> CloudSave {
        CloudSave(board: board, score: score, bestScore: score, won: false, gameOver: false, moves: moves, baseRevision: baseRevision)
    }

    private func api(_ transport: FakeTransport, store: MemoryTokenStore = MemoryTokenStore()) -> CloudAPI {
        CloudAPI(transport: transport, tokens: store, baseURL: URL(string: "https://api.test")!, deviceID: "ios-test")
    }

    private func json(_ data: Data?) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
    }

    func testRegisteringStoresTokensAndReturnsTheAccount() async throws {
        let transport = FakeTransport([(201, sessionBody)])
        let store = MemoryTokenStore()

        let session = try await api(transport, store: store).register(username: "ada", email: "ada@example.test", password: "Password1")

        XCTAssertEqual(session.user.username, "ada")
        XCTAssertEqual(session.user.displayName, "Ada")
        XCTAssertEqual(session.user.statistics.bestScore, 900)
        XCTAssertEqual(store.read()?.accessToken, "access-1")
        XCTAssertEqual(transport.calls[0].method, "POST")
        XCTAssertEqual(transport.calls[0].url.absoluteString, "https://api.test/api/v1/auth/register")
        XCTAssertEqual(json(transport.calls[0].body)["client"] as? String, "ios")
    }

    func testWhitespaceIsTrimmedBeforeItBecomesAUsername() async throws {
        let transport = FakeTransport([(201, sessionBody)])
        _ = try await api(transport).register(username: "  ada  ", email: "  ada@example.test ", password: "Password1")

        let body = json(transport.calls[0].body)
        XCTAssertEqual(body["username"] as? String, "ada")
        XCTAssertEqual(body["email"] as? String, "ada@example.test")
    }

    func testPlayerWithNoDisplayNameIsShownByUsername() async throws {
        let transport = FakeTransport([(200, #"{"user":{"username":"bob","displayName":""},"accessToken":"a","refreshToken":"r"}"#)])
        let session = try await api(transport).login(identifier: "bob", password: "Password1")
        XCTAssertEqual(session.user.displayName, "bob")
    }

    func testRejectedSignInSurfacesServerCodeAndMessage() async {
        let transport = FakeTransport([(401, #"{"error":{"code":"invalid_credentials","message":"That email or password is not correct."}}"#)])

        do {
            _ = try await api(transport).login(identifier: "ada", password: "wrong")
            XCTFail("expected CloudError")
        } catch let error as CloudError {
            XCTAssertEqual(error.code, "invalid_credentials")
            XCTAssertEqual(error.status, 401)
            XCTAssertTrue(error.message.contains("not correct"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testUnparsableErrorBodyStillProducesUsableError() async {
        let transport = FakeTransport([(502, "<html>bad gateway</html>")])

        do {
            _ = try await api(transport).login(identifier: "ada", password: "x")
            XCTFail("expected CloudError")
        } catch let error as CloudError {
            XCTAssertEqual(error.code, "http_error")
            XCTAssertTrue(error.message.contains("502"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testDroppedConnectionIsNetworkFailureNotCrash() async {
        let transport = FakeTransport()
        transport.throwNetworkError = true

        do {
            _ = try await api(transport).login(identifier: "ada", password: "x")
            XCTFail("expected CloudError")
        } catch let error as CloudError {
            XCTAssertTrue(error.isNetworkFailure)
            XCTAssertTrue(error.message.contains("still saved on this device"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testAuthenticatedCallWithoutSessionFailsBeforeNetwork() async {
        let transport = FakeTransport()

        do {
            _ = try await api(transport).sync(save())
            XCTFail("expected CloudError")
        } catch let error as CloudError {
            XCTAssertEqual(error.status, 401)
            XCTAssertTrue(transport.calls.isEmpty)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testExpiredAccessTokenIsRefreshedOnceAndRetried() async throws {
        let transport = FakeTransport([
            (401, #"{"error":{"code":"unauthorized","message":"expired"}}"#),
            (200, #"{"accessToken":"access-2","refreshToken":"refresh-2","user":{"username":"ada"}}"#),
            (200, #"{"resolution":"uploaded","save":{"board":[],"score":10,"revision":3}}"#)
        ])
        let store = MemoryTokenStore(CloudTokens(accessToken: "stale", refreshToken: "refresh-1"))

        let result = try await api(transport, store: store).sync(save())

        XCTAssertEqual(result.resolution, .uploaded)
        XCTAssertEqual(transport.calls.count, 3)
        XCTAssertEqual(transport.calls[1].url.absoluteString, "https://api.test/api/v1/auth/refresh")
        XCTAssertEqual(transport.calls[2].headers["Authorization"], "Bearer access-2")
        XCTAssertEqual(store.read()?.accessToken, "access-2")
    }

    func testRejectedRefreshSignsPlayerOutRatherThanLooping() async {
        let transport = FakeTransport([
            (401, #"{"error":{"code":"unauthorized","message":"expired"}}"#),
            (401, #"{"error":{"code":"unauthorized","message":"that session is gone"}}"#)
        ])
        let store = MemoryTokenStore(CloudTokens(accessToken: "stale", refreshToken: "dead"))

        do {
            _ = try await api(transport, store: store).sync(save())
            XCTFail("expected CloudError")
        } catch {
            XCTAssertNil(store.read(), "an unusable session must be discarded")
            XCTAssertEqual(transport.calls.count, 2)
        }
    }

    func testDroppedConnectionDuringRefreshDoesNotSignPlayerOut() async {
        // Someone on a train has not been signed out; they are simply offline.
        let hybrid = NetworkOnRefreshTransport()
        let store = MemoryTokenStore(CloudTokens(accessToken: "stale", refreshToken: "refresh-1"))

        do {
            _ = try await CloudAPI(transport: hybrid, tokens: store, baseURL: URL(string: "https://api.test")!).sync(save())
            XCTFail("expected CloudError")
        } catch {
            XCTAssertNotNil(store.read(), "the tokens must survive a failed reachability check")
        }
    }

    func testRefreshingWithHalfWrittenTokenFailsCleanly() async {
        let transport = FakeTransport([(401, #"{"error":{"code":"unauthorized","message":"expired"}}"#)])
        let store = MemoryTokenStore(CloudTokens(accessToken: "access", refreshToken: ""))

        do {
            _ = try await api(transport, store: store).sync(save())
            XCTFail("expected CloudError")
        } catch let error as CloudError {
            XCTAssertEqual(error.status, 401)
            XCTAssertNil(store.read())
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testSyncSendsFlatBoardAndDeviceId() async throws {
        let transport = FakeTransport([(200, #"{"resolution":"in_sync","save":null}"#)])
        let store = MemoryTokenStore(CloudTokens(accessToken: "a", refreshToken: "r"))

        _ = try await api(transport, store: store).sync(save(baseRevision: 2))

        let body = json(transport.calls[0].body)
        let saveBody = body["save"] as? [String: Any]
        XCTAssertEqual(body["slot"] as? String, "current")
        XCTAssertEqual(body["strategy"] as? String, "auto")
        XCTAssertEqual(saveBody?["board"] as? [Int], board)
        XCTAssertEqual(saveBody?["client"] as? String, "ios")
        XCTAssertEqual(saveBody?["deviceId"] as? String, "ios-test")
        XCTAssertEqual(saveBody?["baseRevision"] as? Int, 2)
    }

    func testLeaderboardIsReadableSignedOut() async throws {
        let transport = FakeTransport([(200, #"{"entries":[{"rank":1,"username":"ada","displayName":"Ada","score":900,"highestTile":256}],"summary":{"players":1,"topScore":900}}"#)])

        let page = try await api(transport).leaderboard()

        XCTAssertEqual(page.entries.count, 1)
        XCTAssertEqual(page.entries[0].displayName, "Ada")
        XCTAssertEqual(page.players, 1)
        XCTAssertNil(transport.calls[0].headers["Authorization"])
    }

    func testLogoutClearsTokensEvenIfServerRevokeFails() async {
        let transport = FakeTransport([(500, #"{"error":{"code":"boom","message":"no"}}"#)])
        let store = MemoryTokenStore(CloudTokens(accessToken: "a", refreshToken: "r"))

        await api(transport, store: store).logout()

        XCTAssertNil(store.read())
        XCTAssertEqual(transport.calls.count, 1)
    }

    func testSubmitScoreSendsBoardUnderAuth() async throws {
        let transport = FakeTransport([(200, "{}")])
        let store = MemoryTokenStore(CloudTokens(accessToken: "a", refreshToken: "r"))

        try await api(transport, store: store).submitScore(save(), durationSeconds: 42)

        let body = json(transport.calls[0].body)
        XCTAssertEqual(body["score"] as? Int, 5600)
        XCTAssertEqual(body["durationSeconds"] as? Int, 42)
        XCTAssertEqual(body["client"] as? String, "ios")
        XCTAssertEqual(transport.calls[0].headers["Authorization"], "Bearer a")
    }

    func testConflictedSyncPreservesConflictSlot() async throws {
        let transport = FakeTransport([(200, #"{"resolution":"conflicted","conflictSlot":"conflict-1","winner":"remote","save":{"board":[2],"score":1,"revision":9}}"#)])
        let store = MemoryTokenStore(CloudTokens(accessToken: "a", refreshToken: "r"))

        let result = try await api(transport, store: store).sync(save())

        XCTAssertEqual(result.resolution, .conflicted)
        XCTAssertEqual(result.conflictSlot, "conflict-1")
        XCTAssertEqual(result.winner, "remote")
        XCTAssertEqual(result.save?.revision, 9)
    }

    func testCurrentUserReturnsNilWithoutTokens() async throws {
        let transport = FakeTransport()
        let user = try await api(transport).currentUser()
        XCTAssertNil(user)
        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testAuthenticatedLeaderboardSendsBearer() async throws {
        let transport = FakeTransport([(200, #"{"entries":[],"summary":{"players":0,"topScore":0}}"#)])
        let store = MemoryTokenStore(CloudTokens(accessToken: "tok", refreshToken: "r"))

        _ = try await api(transport, store: store).leaderboard(period: "daily")

        XCTAssertEqual(transport.calls[0].headers["Authorization"], "Bearer tok")
        XCTAssertTrue(transport.calls[0].url.absoluteString.contains("period=daily"))
    }
}

/// First call returns 401; the refresh attempt throws a network error.
private final class NetworkOnRefreshTransport: HTTPTransport, @unchecked Sendable {
    private var seen = 0

    func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (Int, Data) {
        seen += 1
        if seen == 1 {
            return (401, Data(#"{"error":{"code":"unauthorized","message":"expired"}}"#.utf8))
        }
        throw CloudError.network
    }
}
