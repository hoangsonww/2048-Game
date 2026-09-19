import Foundation

/// The state the account surface renders, and the orchestration behind it.
///
/// `@MainActor` because every property here drives SwiftUI. The network work
/// happens inside the `CloudAPI` actor; this type only awaits it, so there is
/// exactly one place a state write can occur and it is always the main actor.
@MainActor
final class CloudController: ObservableObject {
    enum Phase: Equatable { case signedOut, working, signedIn }

    @Published private(set) var phase: Phase = .signedOut
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

    /// Whether the guest prompt should be shown. An invitation, never a gate.
    var showGuestPrompt: Bool { isSignedIn == false && promptDismissed == false }

    func dismissPrompt() {
        store.promptDismissed = true
        promptDismissed = true
    }

    func clearAuthError() { authError = nil }

    // MARK: - Session

    /// Re-establishes a stored session on launch, then reconciles.
    func restore(save: @escaping () -> CloudSave, apply: @escaping (CloudSave) -> Void) async {
        guard store.hasTokens else { return }
        phase = .working

        do {
            guard let restored = try await api.currentUser() else {
                phase = .signedOut
                return
            }
            user = restored
            phase = .signedIn
            await sync(save: save, apply: apply)
        } catch let error as CloudError {
            phase = .signedOut
            // A dropped connection has not signed anybody out — the stored
            // token is untouched and the next launch will try again. A
            // rejected one has, and `CloudAPI` already discarded it.
            status = error.isNetworkFailure
                ? "Offline. Your round is saved on this device and will sync when you reconnect."
                : "Your session expired. Sign in again to keep syncing."
        } catch {
            phase = .signedOut
        }
    }

    func register(username: String, email: String, password: String, save: @escaping () -> CloudSave, apply: @escaping (CloudSave) -> Void) async {
        await authenticate({ try await self.api.register(username: username, email: email, password: password) }, save: save, apply: apply)
    }

    func login(identifier: String, password: String, save: @escaping () -> CloudSave, apply: @escaping (CloudSave) -> Void) async {
        await authenticate({ try await self.api.login(identifier: identifier, password: password) }, save: save, apply: apply)
    }

    private func authenticate(
        _ work: @escaping () async throws -> CloudSession,
        save: @escaping () -> CloudSave,
        apply: @escaping (CloudSave) -> Void
    ) async {
        authError = nil
        phase = .working

        do {
            let session = try await work()
            user = session.user
            phase = .signedIn
            dismissPrompt()
            // Signing in is exactly when the two sides are most likely to
            // disagree, so it runs a full reconciliation.
            await sync(save: save, apply: apply)
        } catch let error as CloudError {
            phase = .signedOut
            authError = error.message
        } catch {
            phase = .signedOut
            authError = error.localizedDescription
        }
    }

    func signOut() async {
        user = nil
        phase = .signedOut
        lastResolution = nil
        status = "Signed out. Your round stays on this device."
        await api.logout()
    }

    // MARK: - Game data

    func sync(save: @escaping () -> CloudSave, apply: @escaping (CloudSave) -> Void, strategy: String = "auto") async {
        guard isSignedIn else { return }
        do {
            let result = try await api.sync(save(), strategy: strategy)
            lastResolution = result.resolution
            status = describe(result.resolution)
            // A download replaces the round. An upload does not touch the
            // board — this device is already showing what it sent.
            if result.resolution == .downloaded, let remote = result.save { apply(remote) }
        } catch let error as CloudError {
            status = error.message
        } catch {
            status = error.localizedDescription
        }
    }

    func submitRound(_ save: CloudSave, durationSeconds: Int = 0) async {
        guard isSignedIn, save.score > 0 else { return }
        // A round that fails to reach the leaderboard is a shame, not something
        // the player needs to action: the score is already on their screen.
        try? await api.submitScore(save, durationSeconds: durationSeconds)
    }

    func loadLeaderboard(period: String? = nil) async {
        leaderboardPeriod = period ?? leaderboardPeriod
        leaderboardNote = "Loading…"

        do {
            let page = try await api.leaderboard(period: leaderboardPeriod)
            leaderboard = page
            leaderboardNote = page.entries.isEmpty
                ? "No rounds in this window yet. Finish a game to be the first."
                : "\(page.players.formatted()) players · top score \(page.topScore.formatted())"
        } catch let error as CloudError {
            leaderboard = nil
            leaderboardNote = error.message
        } catch {
            leaderboard = nil
            leaderboardNote = error.localizedDescription
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
