import Foundation

/// The state the account surface renders, and the orchestration behind it.
///
/// `@MainActor` because every property here drives SwiftUI. The network work
/// happens inside the `CloudAPI` actor; this type only awaits it, so there is
/// exactly one place a state write can occur and it is always the main actor.
@MainActor
final class CloudController: ObservableObject {
    enum Phase: Equatable { case signedOut, working, signedIn }
    enum Activity: Equatable {
        case idle
        case authenticating
        case syncing
        case loadingLeaderboard
        case signingOut
    }

    @Published private(set) var phase: Phase = .signedOut
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var user: CloudUser?
    @Published private(set) var status = "Playing on this device. Your round is saved locally."
    @Published private(set) var lastResolution: SyncResolution?
    @Published var authError: String?
    @Published private(set) var leaderboard: LeaderboardPage?
    @Published private(set) var leaderboardNote = ""
    @Published private(set) var leaderboardPeriod = "all"
    @Published private(set) var promptDismissed: Bool

    private let api: CloudAPI
    private let store: UserDefaultsCloudStore
    private var activityDepth = 0

    var isBusy: Bool { activity != .idle }

    init(api: CloudAPI, store: UserDefaultsCloudStore) {
        self.api = api
        self.store = store
        self.promptDismissed = store.promptDismissed
    }

    /// Builds the production controller. Kept separate so a test never has to
    /// construct a real `URLSession` to get a controller.
    static func live(defaults: UserDefaults = .standard, baseURL: URL = CloudAPI.defaultBaseURL) -> CloudController {
        let store = UserDefaultsCloudStore(defaults: defaults)
        return CloudController(api: CloudAPI(tokens: store, baseURL: baseURL), store: store)
    }

    var isSignedIn: Bool { user != nil }

    /// Whether this device is holding tokens from a previous launch.
    ///
    /// The caller needs this *before* the network is asked, because the round
    /// on screen has to belong to the right profile from the first frame —
    /// not from whenever the server answers.
    var hasStoredSession: Bool { store.hasTokens }

    /// Whether the guest prompt should be shown. An invitation, never a gate.
    var showGuestPrompt: Bool { isSignedIn == false && promptDismissed == false }

    func dismissPrompt() {
        store.promptDismissed = true
        promptDismissed = true
    }

    func clearAuthError() { authError = nil }

    private func begin(_ next: Activity) {
        activityDepth += 1
        activity = next
    }

    private func endActivity() {
        activityDepth = max(0, activityDepth - 1)
        if activityDepth == 0 { activity = .idle }
    }

    // MARK: - Session

    /// Re-establishes a stored session on launch.
    ///
    /// Reconciling is the caller's next step, not this one's: which round may
    /// be offered to the server depends on which profile the device adopted,
    /// and that is a decision the game owns.
    @discardableResult
    func restore() async -> Bool {
        guard store.hasTokens else { return false }
        phase = .working
        begin(.syncing)
        status = "Restoring your session…"

        do {
            guard let restored = try await api.currentUser() else {
                phase = .signedOut
                endActivity()
                return false
            }
            user = restored
            phase = .signedIn
            endActivity()
            return true
        } catch let error as CloudError {
            phase = .signedOut
            endActivity()
            // A dropped connection has not signed anybody out — the stored
            // token is untouched and the next launch will try again. A
            // rejected one has, and `CloudAPI` already discarded it.
            status = error.isNetworkFailure
                ? "Offline. Your round is saved on this device and will sync when you reconnect."
                : "Your session expired. Sign in again to keep syncing."
            return false
        } catch {
            phase = .signedOut
            endActivity()
            return false
        }
    }

    @discardableResult
    func register(username: String, email: String, password: String) async -> Bool {
        await authenticate(creating: true) { try await self.api.register(username: username, email: email, password: password) }
    }

    @discardableResult
    func login(identifier: String, password: String) async -> Bool {
        await authenticate(creating: false) { try await self.api.login(identifier: identifier, password: password) }
    }

    private func authenticate(
        creating: Bool,
        _ work: @escaping () async throws -> CloudSession
    ) async -> Bool {
        authError = nil
        phase = .working
        begin(.authenticating)
        status = creating ? "Creating account…" : "Signing in…"

        do {
            let session = try await work()
            user = session.user
            phase = .signedIn
            dismissPrompt()
            // A revision remembered from an earlier session belongs to an
            // earlier session. Carrying it would let the next upload claim to
            // descend from a round this account has never seen.
            store.knownRevision = nil
            endActivity()
            return true
        } catch let error as CloudError {
            phase = .signedOut
            endActivity()
            authError = error.message
            return false
        } catch {
            phase = .signedOut
            endActivity()
            authError = error.localizedDescription
            return false
        }
    }

    /// Loads the account's round, offering the server nothing in return.
    ///
    /// The `nil` local save is the point. A round played before signing in
    /// belongs to the device, not to the account that just signed in on it,
    /// so there is nothing here to merge or conflict with: the server either
    /// hands back the round this account already had, or it has none and the
    /// clean board the game just created stands.
    func adoptAccountRound(apply: @escaping (CloudSave) -> Void) async {
        guard isSignedIn else { return }
        begin(.syncing)
        status = "Syncing…"
        do {
            let result = try await api.sync(nil, strategy: "auto")
            lastResolution = result.resolution
            status = result.save == nil
                ? "Signed in. Your account is ready."
                : "Restored the round from your account."
            if let revision = result.save?.revision, revision > 0 {
                store.knownRevision = revision
            }
            if let remote = result.save { apply(remote) }
            endActivity()
        } catch let error as CloudError {
            endActivity()
            status = error.message
        } catch {
            endActivity()
            status = error.localizedDescription
        }
        await refreshUserQuietly()
    }

    /**
     Resets a forgotten password and ends the session this device was holding.

     Reported through `authError` like the other credential failures, because
     it is the same kind of failure to the player: something they typed did
     not match an account.
     */
    @discardableResult
    func resetPassword(username: String, email: String, newPassword: String) async -> Bool {
        authError = nil
        begin(.authenticating)
        status = "Resetting your password…"

        do {
            try await api.resetPassword(username: username, email: email, newPassword: newPassword)
            // The server revoked every session, this one included.
            user = nil
            phase = .signedOut
            lastResolution = nil
            store.knownRevision = nil
            status = "Password reset. Sign in with your new password."
            endActivity()
            return true
        } catch let error as CloudError {
            endActivity()
            authError = error.message
            phase = isSignedIn ? .signedIn : .signedOut
            return false
        } catch {
            endActivity()
            authError = error.localizedDescription
            phase = isSignedIn ? .signedIn : .signedOut
            return false
        }
    }

    func signOut() async {
        begin(.signingOut)
        user = nil
        phase = .signedOut
        lastResolution = nil
        store.knownRevision = nil
        status = "Signed out. Your device's own round is back."
        await api.logout()
        endActivity()
    }

    // MARK: - Game data

    /// Explicit Sync now: push this device's board and refresh career totals.
    func syncNow(save: @escaping () -> CloudSave, apply: @escaping (CloudSave) -> Void) async {
        await sync(save: save, apply: apply, strategy: "prefer-local")
        await refreshUserQuietly()
    }

    func sync(save: @escaping () -> CloudSave, apply: @escaping (CloudSave) -> Void, strategy: String = "auto") async {
        guard isSignedIn else { return }
        begin(.syncing)
        status = "Syncing…"
        var local = save()
        if let revision = store.knownRevision {
            local.baseRevision = revision
        }
        do {
            let result = try await api.sync(local, strategy: strategy)
            lastResolution = result.resolution
            status = describe(result.resolution)
            if let revision = result.save?.revision, revision > 0 {
                store.knownRevision = revision
            }
            if shouldApply(result), let remote = result.save { apply(remote) }
            endActivity()
        } catch let error as CloudError {
            endActivity()
            status = error.message
        } catch {
            endActivity()
            status = error.localizedDescription
        }
    }

    func submitRound(_ save: CloudSave, durationSeconds: Int = 0) async {
        guard isSignedIn, save.score > 0 else { return }
        // A round that fails to reach the leaderboard is a shame, not something
        // the player needs to action: the score is already on their screen.
        try? await api.submitScore(save, durationSeconds: durationSeconds)
        await refreshUserQuietly()
    }

    func loadLeaderboard(period: String? = nil) async {
        leaderboardPeriod = period ?? leaderboardPeriod
        leaderboardNote = "Loading…"
        begin(.loadingLeaderboard)

        do {
            let page = try await api.leaderboard(period: leaderboardPeriod)
            leaderboard = page
            leaderboardNote = page.entries.isEmpty
                ? "No rounds in this window yet. Finish a game to be the first."
                : "\(page.players.formatted()) players · top score \(page.topScore.formatted())"
            endActivity()
        } catch let error as CloudError {
            leaderboard = nil
            leaderboardNote = error.message
            endActivity()
        } catch {
            leaderboard = nil
            leaderboardNote = error.localizedDescription
            endActivity()
        }
    }

    /// Reloads career totals from the account.
    ///
    /// What the server returns replaces what was held, with no local maximum
    /// merged in. Career statistics belong to the account; folding this
    /// device's best score into them is how an account that had played
    /// nothing ended up advertising a best score and a highest tile it never
    /// earned.
    private func refreshUserQuietly() async {
        guard isSignedIn else { return }
        if let refreshed = try? await api.currentUser() {
            user = refreshed
        }
    }

    private func shouldApply(_ result: SyncResult) -> Bool {
        switch result.resolution {
        case .downloaded: return true
        case .conflicted: return result.winner == "remote"
        default: return false
        }
    }

    private func describe(_ resolution: SyncResolution) -> String {
        switch resolution {
        case .uploaded: return "Round saved to your account."
        case .downloaded: return "Restored the round from your account."
        case .inSync: return "Everything is in sync."
        case .conflicted:
            return "Two devices had different rounds — the further one was kept, and the other is safe in your saves."
        }
    }
}
