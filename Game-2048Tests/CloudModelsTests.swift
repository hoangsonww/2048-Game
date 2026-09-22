import XCTest
@testable import Game_2048

/// Wire-format decoding. A field the server adds later must not break a build
/// that predates it, so every optional path here is intentional.
final class CloudModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testCloudSaveDecodesSparsePayloadWithDefaults() throws {
        let save = try decode(#"{"board":[2,4],"score":10}"#, as: CloudSave.self)
        XCTAssertEqual(save.board, [2, 4])
        XCTAssertEqual(save.score, 10)
        XCTAssertEqual(save.bestScore, 0)
        XCTAssertFalse(save.won)
        XCTAssertFalse(save.gameOver)
        XCTAssertEqual(save.moves, 0)
        XCTAssertEqual(save.elapsedSeconds, 0)
        XCTAssertNil(save.baseRevision)
        XCTAssertEqual(save.revision, 0)
    }

    func testCloudSaveDecodesFullPayloadAndGridHelper() throws {
        let save = try decode(
            #"{"board":[2,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"score":40,"bestScore":100,"won":true,"gameOver":false,"moves":5,"elapsedSeconds":12,"baseRevision":3,"revision":4}"#,
            as: CloudSave.self
        )
        XCTAssertEqual(save.grid[0], [2, 4, 0, 0])
        XCTAssertEqual(save.baseRevision, 3)
        XCTAssertEqual(save.revision, 4)
        XCTAssertTrue(save.won)
    }

    func testCloudSaveRoundTripsThroughEncoder() throws {
        let original = CloudSave(
            board: Array(repeating: 0, count: 16),
            score: 8,
            bestScore: 64,
            won: false,
            gameOver: false,
            moves: 2,
            elapsedSeconds: 1,
            baseRevision: 1,
            revision: 2
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CloudSave.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCloudUserFallsBackToUsernameWhenDisplayNameMissing() throws {
        let user = try decode(
            #"{"id":"1","username":"ada","displayName":"","email":"a@b.c","statistics":{"bestScore":9}}"#,
            as: CloudUser.self
        )
        XCTAssertEqual(user.displayName, "ada")
        XCTAssertEqual(user.statistics.bestScore, 9)
        XCTAssertEqual(user.statistics.gamesPlayed, 0)
    }

    func testCloudUserMemberwiseInitAlsoFallsBack() {
        let user = CloudUser(username: "bob", displayName: "")
        XCTAssertEqual(user.displayName, "bob")
    }

    func testCloudStatisticsDefaultsOnEmptyObject() throws {
        let stats = try decode("{}", as: CloudStatistics.self)
        XCTAssertEqual(stats, CloudStatistics())
    }

    func testSyncResolutionMapsUnknownStringsToInSync() {
        XCTAssertEqual(SyncResolution(rawValue: "uploaded"), .uploaded)
        XCTAssertEqual(SyncResolution(rawValue: "downloaded"), .downloaded)
        XCTAssertEqual(SyncResolution(rawValue: "conflicted"), .conflicted)
        XCTAssertEqual(SyncResolution(rawValue: "in_sync"), .inSync)
        XCTAssertEqual(SyncResolution(rawValue: "something_new"), .inSync)
    }

    func testLeaderboardEntryIdentityUsesRankAndUsername() {
        let entry = LeaderboardEntry(rank: 2, username: "ada", displayName: "Ada", score: 100, highestTile: 64, isViewer: true)
        XCTAssertEqual(entry.id, "2-ada")
    }

    func testCloudErrorFlags() {
        XCTAssertTrue(CloudError.network.isNetworkFailure)
        XCTAssertTrue(CloudError.unauthorized.isUnauthorized)
        XCTAssertFalse(CloudError(code: "x", message: "y", status: 500).isUnauthorized)
    }
}

// MARK: - Focused maintainer notes (documentation only)
//
// Cloud model test maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Cover both sparse backward-compatible payloads and complete current payloads.
//
// 02. Round-trip encodable models whenever upload and download share the same representation.
//
// 03. Assert fallback display names and defaults directly rather than through a view.
//
// 04. Exercise unknown enum values to protect forward compatibility.
//
// 05. Keep identity tests stable for list diffing and leaderboard presentation.
//
// 06. Test error classification separately from user-facing message text.
//
// Symbol and scenario index
//
// 01. `final class CloudModelsTests: XCTestCase`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 03. `func testCloudSaveDecodesSparsePayloadWithDefaults() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 04. `func testCloudSaveDecodesFullPayloadAndGridHelper() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 05. `func testCloudSaveRoundTripsThroughEncoder() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 06. `func testCloudUserFallsBackToUsernameWhenDisplayNameMissing() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 07. `func testCloudUserMemberwiseInitAlsoFallsBack()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 08. `func testCloudStatisticsDefaultsOnEmptyObject() throws`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 09. `func testSyncResolutionMapsUnknownStringsToInSync()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 10. `func testLeaderboardEntryIdentityUsesRankAndUsername()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 11. `func testCloudErrorFlags()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
