import Foundation

/// The device-local half of the cloud layer: two tokens and one dismissal.
///
/// `UserDefaults` rather than the Keychain, deliberately. The Keychain would
/// add an entitlement, a migration, and a class of "item not found" failure
/// mode, to protect a token whose worst case is an attacker who already has
/// the device unlocked seeing someone's 2048 scores. The saved round already
/// lives here for the same reason. This is recorded in `docs/backend.md` so
/// it reads as a decision rather than an oversight.
final class UserDefaultsCloudStore: TokenStoring {
    private enum Key {
        static let access = "cloudAccessTokenV1"
        static let refresh = "cloudRefreshTokenV1"
        static let prompt = "cloudPromptDismissedV1"
        static let revision = "cloudKnownRevisionV1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func read() -> CloudTokens? {
        guard let access = defaults.string(forKey: Key.access),
              let refresh = defaults.string(forKey: Key.refresh),
              access.isEmpty == false,
              // An access token with no refresh alongside it cannot be renewed,
              // so reporting it as a session would strand the player on a
              // token that expires and never recovers.
              refresh.isEmpty == false
        else { return nil }
        return CloudTokens(accessToken: access, refreshToken: refresh)
    }

    func write(_ tokens: CloudTokens?) {
        guard let tokens else {
            defaults.removeObject(forKey: Key.access)
            defaults.removeObject(forKey: Key.refresh)
            return
        }
        defaults.set(tokens.accessToken, forKey: Key.access)
        defaults.set(tokens.refreshToken, forKey: Key.refresh)
    }

    var hasTokens: Bool { read() != nil }

    var promptDismissed: Bool {
        get { defaults.bool(forKey: Key.prompt) }
        set { defaults.set(newValue, forKey: Key.prompt) }
    }

    /// Last revision this device successfully synced — sent as `baseRevision`.
    var knownRevision: Int? {
        get {
            guard defaults.object(forKey: Key.revision) != nil else { return nil }
            let value = defaults.integer(forKey: Key.revision)
            return value > 0 ? value : nil
        }
        set {
            if let newValue, newValue > 0 {
                defaults.set(newValue, forKey: Key.revision)
            } else {
                defaults.removeObject(forKey: Key.revision)
            }
        }
    }
}

// MARK: - Focused maintainer notes (documentation only)
//
// Credential storage maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Store access and refresh tokens as one logical session; a partial pair is not
//     authenticated state.
//
// 02. Clear both token keys together so sign-out cannot leave a half-valid credential behind.
//
// 03. Keep prompt dismissal separate from credentials because it belongs to local presentation
//     state.
//
// 04. Use injected UserDefaults suites in tests to prevent state leaking between test cases.
//
// 05. Never place passwords, profile data, boards, or career statistics in this token store.
//
// 06. Changes to storage keys require an explicit migration or a deliberate safe sign-out.
//
// Symbol and scenario index
//
// 01. `final class UserDefaultsCloudStore: TokenStoring`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `init(defaults: UserDefaults = .standard)`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 03. `func read() -> CloudTokens?`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 04. `func write(_ tokens: CloudTokens?)`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
