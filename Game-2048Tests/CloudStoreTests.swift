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
