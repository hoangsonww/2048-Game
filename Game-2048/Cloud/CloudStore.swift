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
