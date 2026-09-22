import XCTest
@testable import Game_2048

/// The device-local half of the cloud layer.
final class CloudStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "CloudStoreTests"

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

    func testEmptyStoreReportsNoSession() {
        let store = UserDefaultsCloudStore(defaults: defaults)
        XCTAssertNil(store.read())
        XCTAssertFalse(store.hasTokens)
        XCTAssertFalse(store.promptDismissed)
    }

    func testRoundTripKeepsBothTokens() {
        let store = UserDefaultsCloudStore(defaults: defaults)
        store.write(CloudTokens(accessToken: "access", refreshToken: "refresh"))

        let tokens = store.read()
        XCTAssertEqual(tokens?.accessToken, "access")
        XCTAssertEqual(tokens?.refreshToken, "refresh")
        XCTAssertTrue(store.hasTokens)
    }

    func testAccessTokenAloneIsNotASession() {
        // A half-written entry cannot be renewed, so it must not look signed in.
        defaults.set("access-only", forKey: "cloudAccessTokenV1")
        let store = UserDefaultsCloudStore(defaults: defaults)

        XCTAssertNil(store.read())
        XCTAssertFalse(store.hasTokens)
    }

    func testEmptyTokensAreNotASession() {
        defaults.set("", forKey: "cloudAccessTokenV1")
        defaults.set("", forKey: "cloudRefreshTokenV1")
        let store = UserDefaultsCloudStore(defaults: defaults)

        XCTAssertNil(store.read())
    }

    func testClearingRemovesBothTokens() {
        let store = UserDefaultsCloudStore(defaults: defaults)
        store.write(CloudTokens(accessToken: "a", refreshToken: "r"))
        store.write(nil)

        XCTAssertNil(store.read())
        XCTAssertNil(defaults.string(forKey: "cloudAccessTokenV1"))
        XCTAssertNil(defaults.string(forKey: "cloudRefreshTokenV1"))
    }

    func testPromptDismissalIsRemembered() {
        let store = UserDefaultsCloudStore(defaults: defaults)
        store.promptDismissed = true
        XCTAssertTrue(UserDefaultsCloudStore(defaults: defaults).promptDismissed)
    }
}

// MARK: - Focused maintainer notes (documentation only)
//
// Cloud storage test maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Use an isolated defaults suite for every test run.
//
// 02. Verify both token keys on write, read, partial state, and clear.
//
// 03. Treat empty strings as missing credentials.
//
// 04. Keep prompt-dismissal coverage independent of authentication coverage.
//
// 05. Remove persistent domains in teardown so reruns remain hermetic.
//
// 06. Add migration coverage before changing any persisted key.
//
// Symbol and scenario index
//
// 01. `final class CloudStoreTests: XCTestCase`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `func testEmptyStoreReportsNoSession()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 03. `func testRoundTripKeepsBothTokens()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 04. `func testAccessTokenAloneIsNotASession()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 05. `func testEmptyTokensAreNotASession()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 06. `func testClearingRemovesBothTokens()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 07. `func testPromptDismissalIsRemembered()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
