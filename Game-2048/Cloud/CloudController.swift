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

// MARK: - Maintainer reference (documentation only)
//
// Release, security, privacy, and delivery reference.
//
// This section is intentionally comment-only. The named repository files remain
// canonical; their contents are mirrored here as an in-source reading reference.
// No declaration, executable statement, build setting, or runtime behavior follows.

// SOURCE: docs/releasing.md

// # Releasing
//
// Releases used to be made by hand: tag whatever `main` happened to be, write the
// notes, and stop. Nothing was attached, so there was nothing to download — the
// Android app could only be had by installing a JDK and the Android SDK and
// building it yourself, and the iOS app not at all.
//
// There is now one button. It moves the version, tags, builds all three clients,
// attaches their artifacts, and refuses to report success unless a release with
// those files actually exists.
//
// ## Cutting a release
//
// Actions → **Cut release** → Run workflow. Choose `patch`, `minor`, or `major`.
// Leave `dry_run` off to publish; turn it on to see what would happen without
// tagging or pushing anything.
//
// That is the whole procedure. Do not tag by hand.
//
// ## The version
//
// `VERSION` at the repository root is the only place a human edits the version.
// Everything else is derived from it by `scripts/version.sh`:
//
// | Where | What it sets |
// | --- | --- |
// | `package.json` | `version` |
// | `Android-Version/Game2048/app/build.gradle.kts` | `versionName`, `versionCode` |
// | `2048 Game.xcodeproj/project.pbxproj` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, in every build configuration |
//
// `versionCode` is derived rather than tracked separately: `MAJOR * 10000 +
// MINOR * 100 + PATCH`, so 2.1.3 becomes 20103. It stays monotonic as long as
// minor and patch remain below 100, and there is no second number to forget.
//
// ```bash
// make version        # print the version and check every client agrees
// make version-sync   # rewrite the derived files from VERSION
// scripts/version.sh set 2.1.0
// scripts/version.sh bump minor
// ```
//
// The check is not advisory. It runs in `make check`, in CI on every push and
// pull request, and again at the tag before any artifact is built. These files
// had drifted four ways at once — `package.json` said 1.2.0, Android said 1.0
// with a `versionCode` of 1, Xcode said 1.0, and the newest release was v2.0.0 —
// which is the failure the gate exists to prevent recurring.
//
// ## What each release contains
//
// | Artifact | Built by | Notes |
// | --- | --- | --- |
// | `2048-vX.Y.Z-debug.apk` | `android-apk` | Installable on any device with unknown sources enabled |
// | `2048-vX.Y.Z-ios-unsigned.zip` | `ios-app` | Unsigned `.app` for the simulator, or to sign yourself |
// | `2048-vX.Y.Z-web.zip` | `web-bundle` | The shipping web client — unzip and serve the folder |
// | `SHA256SUMS-ios.txt`, `SHA256SUMS-web.txt` | those jobs | Checksums for the two zips |
//
// The iOS artifact is deliberately unsigned. Signing needs a provisioning profile
// and a team identifier, neither of which belongs in a public repository, so App
// Store distribution stays a manual step outside this pipeline.
//
// ## How it fits together
//
// ```
// Cut release (workflow_dispatch)
//   ├─ version.sh check          the tree must agree with itself first
//   ├─ bump VERSION, propagate, open the changelog section
//   ├─ commit + tag vX.Y.Z + push
//   ├─ dispatch Release at the tag
//   └─ wait, then confirm a release exists with its artifacts attached
//         │
//         └─ Release
//              ├─ prepare       resolve the tag, check it matches VERSION, create the release
//              ├─ android-apk   ─┐
//              ├─ ios-app        ├─ build, then upload into the existing release
//              ├─ web-bundle    ─┘
//              └─ verify        every expected file is attached, or the run fails
// ```
//
// Three details in there are not decoration:
//
// **A tag pushed by a workflow starts nothing.** GitHub suppresses workflow
// triggers for events raised by `GITHUB_TOKEN`, to stop workflows retriggering
// themselves. So `Cut release` cannot push the tag and walk away — it dispatches
// `Release` by name, at that tag. Dispatching also needs `actions: write`;
// `actions: read` gets a 403.
//
// **One job creates the release, three upload into it.** Letting each build job
// create-if-missing reads as harmless and is a race: all three start together,
// all three see no release, and two fail with "already exists". That is an
// intermittent red cross that says nothing about the code.
//
// **A green build is not a release.** The `verify` job looks at what is attached
// to the release, not at whether the jobs reported success — and `Cut release`
// checks again afterwards. An earlier version of this pipeline in a sibling
// repository reported success having published nothing at all, which is worse
// than failing, because nobody goes looking.
//
// ## When something fails
//
// The pipeline is designed so that a failure leaves a diagnosable state rather
// than a half-published release.
//
// - **`version.sh check` fails at the start** — the tree disagrees with itself.
//   Run `make version-sync`, commit, and cut again. Nothing was pushed.
// - **The tag already exists** — `Cut release` refuses rather than moving it.
//   Bump past it.
// - **A build job fails** — the release exists with fewer artifacts, and `verify`
//   fails naming the missing file. Fix the build, then re-run `Release` via
//   `workflow_dispatch` with that tag; uploads use `--clobber`, so re-running is
//   safe and idempotent.
// - **`Cut release` times out waiting** — it waits 40 minutes. The tag and commit
//   are already pushed; check the `Release` run and re-dispatch it if needed.
// - **The dispatch cannot find the tag** — retried six times over a minute, since
//   the tag was pushed seconds earlier and the API resolving `--ref` can lag its
//   own push. If all six fail the job says so and names the tag to re-dispatch by
//   hand; the bump itself is already committed, so do not cut again.
//
// Re-running `Release` at an existing tag is always safe. It rebuilds from the
// tag, so it produces the same artifacts, and replaces rather than duplicates
// them.

// SOURCE: docs/privacy.md

// # Privacy
//
// How 2048 handles data, with and without an account.
//
// ## Default: local-only play
//
// With no account, **nothing leaves the device**.
//
// - No sign-in, no user identifiers, no analytics SDK, no advertising SDK, no crash reporter
// - The round and best score live in `localStorage` (web), `UserDefaults` (iOS), or `SharedPreferences` (Android)
// - Clearing site data or deleting the app removes that state
// - The web client may fetch Google Fonts for the display typeface; the game remains playable if that request is blocked
//
// ## Optional account
//
// An account is offered under the board as an invitation. Declining it, or dismissing the prompt, leaves play exactly as before.
//
// When someone creates an account, the API stores:
//
// | Data | Purpose |
// | --- | --- |
// | Username, email, password hash (bcrypt) | Sign-in |
// | Display name and public profile fields | Leaderboard / social |
// | Cloud save slots (board, score, moves, flags) | Cross-device continuity |
// | Submitted scores | Leaderboards |
// | Achievement unlocks and aggregate statistics | Account screen |
// | Refresh-token hashes and session metadata | Auth rotation |
// | Optional coarse event kinds (no board content) | Product questions; TTL 90 days |
//
// The API does **not** store device fingerprints for advertising, payment data, or third-party tracking identifiers.
//
// ## Tokens on device
//
// Access and refresh tokens are kept beside the local save:
//
// | Platform | Storage | Why |
// | --- | --- | --- |
// | Web | `localStorage` | Same trust boundary as the saved round |
// | Android | `SharedPreferences` | Matches the existing save store; no EncryptedSharedPreferences migration for a token whose worst case is an unlocked-device read of 2048 scores |
// | iOS | `UserDefaults` | Same reasoning; Keychain would add entitlement and failure modes without a commensurate threat model |
//
// Signing out clears tokens locally and best-effort revokes the refresh token on the server. The local round stays on the device.
//
// ## Network
//
// - Production API: `https://game-2048-cloud-api.vercel.app`
// - Clients send `X-Client: web|android|ios`
// - Offline or failed sync never blocks a move; status text explains and the board keeps working
// - Server-driven help surfaces (iOS / Android) remain content-only with a native fallback — see [ARCHITECTURE.md](../ARCHITECTURE.md#server-driven-surfaces)
//
// ## Deletion
//
// Account deletion (authenticated API) removes the user document and associated saves, scores, achievements, follows, and sessions. Local device state is unchanged until the player clears it themselves.
//
// ## Contact
//
// Security reports: see [SECURITY.md](../.github/SECURITY.md).

// SOURCE: .github/SECURITY.md

// # Security policy
//
// ## Supported versions
//
// Security fixes target the latest commit on the default branch. Historical releases and forks are not actively maintained.
//
// ## Architecture and data
//
// The web client is a static application hosted on GitHub Pages. Play is local-first on web, iOS, and Android: the active round and best score always live in browser or device-local storage, and a move never requires the network.
//
// An optional Cloud API (`server/`, deployed at [game-2048-cloud-api.vercel.app](https://game-2048-cloud-api.vercel.app); `/` redirects to `/docs`) provides accounts, JWT auth, cross-device save sync, scores, and leaderboards. There is no analytics pipeline, advertising SDK, file upload, or payment flow. See [docs/privacy.md](../docs/privacy.md) and [docs/backend.md](../docs/backend.md).
//
// ## Report a vulnerability privately
//
// Use [GitHub private vulnerability reporting](https://github.com/hoangsonww/2048-Game/security/advisories/new). Include the affected platform and revision, reproduction steps, impact, and a minimal proof of concept when safe. Do not open a public issue for an unpatched vulnerability or include credentials, signing keys, or personal data.
//
// The maintainer will acknowledge actionable reports when available, investigate impact, and coordinate disclosure after a fix. Please allow a reasonable remediation window before publishing details.
//
// ## Scope
//
// Useful reports include unsafe state handling, script injection in the web client, auth or sync flaws in the Cloud API, exposed credentials or signing material, malicious dependency behavior, and platform permission issues. Generic automated scan output without a reproducible impact may be closed as informational.

// SOURCE: .github/workflows/release.yml

// name: Release
//
// # Publishes something installable for every client on each tagged release.
// #
// # Android gets an APK so players can try it without a JDK, the Android SDK, or
// # Gradle. iOS gets an unsigned .app zip — a build artifact for the simulator or
// # for someone who will sign it themselves, not an App Store package; Apple's
// # signing and provisioning stay outside this repository. The web client is
// # deployed continuously to Pages, but a zip of it is still worth attaching so a
// # release is a complete, self-contained record of what shipped.
// #
// # The release itself is created once, up front, by `prepare`. The three build
// # jobs only upload into it. Letting each job create-if-missing looks harmless
// # and is a race: they start together, all three see no release, all three call
// # `gh release create`, and two fail with "already exists" — an intermittent red
// # cross that says nothing about the code. One writer, three uploaders.
//
// on:
//   push:
//     tags: ["v*"]
//   workflow_dispatch:
//     inputs:
//       tag:
//         description: "Existing tag to build and attach artifacts to (e.g. v2.1.0)"
//         required: true
//         type: string
//
// permissions:
//   contents: write
//
// concurrency:
//   group: release-${{ inputs.tag || github.ref }}
//   cancel-in-progress: false
//
// jobs:
//   prepare:
//     name: Open the release
//     runs-on: ubuntu-latest
//     timeout-minutes: 10
//     outputs:
//       tag: ${{ steps.resolve.outputs.tag }}
//     steps:
//       - name: Check out repository
//         uses: actions/checkout@v4
//         with:
//           fetch-depth: 0
//
//       # A tag push carries the tag in the ref; a dispatch carries it as input,
//       # because a workflow dispatched at a tag still has to be told which tag it
//       # is publishing.
//       - name: Resolve the release tag
//         id: resolve
//         run: |
//           set -Eeuo pipefail
//           if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
//             TAG="${{ inputs.tag }}"
//           else
//             TAG="${GITHUB_REF_NAME}"
//           fi
//           if ! git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
//             echo "::error::${TAG} is not a tag in this repository."
//             exit 1
//           fi
//           echo "tag=${TAG}" >> "$GITHUB_OUTPUT"
//           echo "Publishing ${TAG}"
//
//       # The tree at the tag must agree with the tag. A release whose APK says
//       # 1.0 while the page says 2.1.0 is worse than no release.
//       - name: Verify the tag matches the version in the tree
//         run: |
//           set -Eeuo pipefail
//           expected="${{ steps.resolve.outputs.tag }}"
//           actual="v$(./scripts/version.sh)"
//           if [ "${expected}" != "${actual}" ]; then
//             echo "::error::Tag ${expected} does not match VERSION (${actual})."
//             exit 1
//           fi
//           ./scripts/version.sh check
//
//       - name: Create the release if it does not exist
//         env:
//           GH_TOKEN: ${{ github.token }}
//         run: |
//           set -Eeuo pipefail
//           TAG="${{ steps.resolve.outputs.tag }}"
//           if gh release view "$TAG" >/dev/null 2>&1; then
//             echo "$TAG already exists; artifacts will be added to it."
//           else
//             gh release create "$TAG" --generate-notes --title "$TAG"
//             echo "Created $TAG"
//           fi
//
//   android-apk:
//     name: Build and attach the Android APK
//     needs: prepare
//     runs-on: ubuntu-latest
//     timeout-minutes: 25
//     defaults:
//       run:
//         working-directory: Android-Version/Game2048
//
//     steps:
//       - name: Check out repository
//         uses: actions/checkout@v4
//         with:
//           ref: ${{ needs.prepare.outputs.tag }}
//
//       - name: Set up Java 17
//         uses: actions/setup-java@v4
//         with:
//           distribution: temurin
//           java-version: 17
//
//       - name: Set up and validate Gradle
//         uses: gradle/actions/setup-gradle@v4
//
//       - name: Verify the client before publishing
//         run: ./gradlew testDebugUnitTest lintDebug --stacktrace
//
//       - name: Assemble the debug APK
//         run: ./gradlew assembleDebug --stacktrace
//
//       - name: Name the APK after the release
//         working-directory: ${{ github.workspace }}
//         run: |
//           set -Eeuo pipefail
//           SRC="Android-Version/Game2048/app/build/outputs/apk/debug/app-debug.apk"
//           test -f "$SRC" || { echo "APK not found at $SRC" >&2; exit 1; }
//           cp "$SRC" "2048-${{ needs.prepare.outputs.tag }}-debug.apk"
//           ls -lh "2048-${{ needs.prepare.outputs.tag }}-debug.apk"
//
//       - name: Upload the APK as a workflow artifact
//         uses: actions/upload-artifact@v4
//         with:
//           name: android-apk
//           path: 2048-${{ needs.prepare.outputs.tag }}-debug.apk
//           if-no-files-found: error
//
//       - name: Attach the APK to the release
//         working-directory: ${{ github.workspace }}
//         env:
//           GH_TOKEN: ${{ github.token }}
//         run: |
//           set -Eeuo pipefail
//           TAG="${{ needs.prepare.outputs.tag }}"
//           gh release upload "$TAG" "2048-${TAG}-debug.apk" --clobber
//
//   ios-app:
//     name: Build and attach the unsigned iOS app
//     needs: prepare
//     runs-on: macos-15
//     timeout-minutes: 30
//     steps:
//       - name: Check out repository
//         uses: actions/checkout@v4
//         with:
//           ref: ${{ needs.prepare.outputs.tag }}
//
//       # Unsigned, for a simulator or for someone who signs it themselves. No
//       # provisioning profile, no team id, no App Store Connect — none of which
//       # can live in a public repository anyway.
//       - name: Build unsigned
//         run: |
//           set -Eeuo pipefail
//           xcodebuild \
//             -project "2048 Game.xcodeproj" \
//             -scheme "Game-2048" \
//             -configuration Release \
//             -destination "generic/platform=iOS Simulator" \
//             -derivedDataPath .build/dd \
//             CODE_SIGNING_ALLOWED=NO \
//             CODE_SIGNING_REQUIRED=NO \
//             CODE_SIGN_IDENTITY=- \
//             build
//
//       - name: Package and attach
//         env:
//           GH_TOKEN: ${{ github.token }}
//         run: |
//           set -Eeuo pipefail
//           TAG="${{ needs.prepare.outputs.tag }}"
//           APP="$(find .build/dd/Build/Products -maxdepth 2 -name '*.app' -print -quit)"
//           test -n "$APP" || { echo "No .app was produced" >&2; exit 1; }
//           ditto -c -k --sequesterRsrc --keepParent "$APP" "2048-${TAG}-ios-unsigned.zip"
//           shasum -a 256 "2048-${TAG}-ios-unsigned.zip" > "SHA256SUMS-ios.txt"
//           gh release upload "$TAG" "2048-${TAG}-ios-unsigned.zip" "SHA256SUMS-ios.txt" --clobber
//
//   web-bundle:
//     name: Package and attach the web client
//     needs: prepare
//     runs-on: ubuntu-latest
//     timeout-minutes: 10
//     steps:
//       - name: Check out repository
//         uses: actions/checkout@v4
//         with:
//           ref: ${{ needs.prepare.outputs.tag }}
//
//       - uses: actions/setup-node@v4
//         with:
//           node-version: 22
//           cache: npm
//
//       - name: Verify before publishing
//         run: |
//           npm ci
//           npm run check
//           npm run test:unit
//
//       # Exactly the files the container serves, so the zip is the shipping web
//       # client rather than a copy of the repository.
//       - name: Package
//         run: |
//           set -Eeuo pipefail
//           TAG="${{ needs.prepare.outputs.tag }}"
//           mkdir -p dist/2048-web
//           cp -R index.html 404.html manifest.json robots.txt sitemap.xml humans.txt \
//                 llms.txt llms-full.txt images Web-Version dist/2048-web/
//           (cd dist && zip -qr "../2048-${TAG}-web.zip" 2048-web)
//           shasum -a 256 "2048-${TAG}-web.zip" > SHA256SUMS-web.txt
//           ls -lh "2048-${TAG}-web.zip"
//
//       - name: Attach
//         env:
//           GH_TOKEN: ${{ github.token }}
//         run: |
//           set -Eeuo pipefail
//           TAG="${{ needs.prepare.outputs.tag }}"
//           gh release upload "$TAG" "2048-${TAG}-web.zip" SHA256SUMS-web.txt --clobber
//
//   # A green build is not a release. This job is the one that decides whether
//   # the release actually happened, by looking at what is attached to it rather
//   # than at whether the jobs above reported success.
//   verify:
//     name: Verify the release is complete
//     needs: [prepare, android-apk, ios-app, web-bundle]
//     runs-on: ubuntu-latest
//     timeout-minutes: 10
//     steps:
//       - name: Check every expected artifact is attached
//         env:
//           GH_TOKEN: ${{ github.token }}
//           GH_REPO: ${{ github.repository }}
//         run: |
//           set -Eeuo pipefail
//           TAG="${{ needs.prepare.outputs.tag }}"
//           assets="$(gh release view "$TAG" --json assets --jq '.assets[].name')"
//           echo "Attached to ${TAG}:"
//           while IFS= read -r asset; do echo "  ${asset}"; done <<< "${assets}"
//
//           missing=0
//           for expected in \
//             "2048-${TAG}-debug.apk" \
//             "2048-${TAG}-ios-unsigned.zip" \
//             "2048-${TAG}-web.zip"; do
//             if ! grep -Fqx "${expected}" <<< "${assets}"; then
//               echo "::error::${expected} is missing from release ${TAG}."
//               missing=1
//             fi
//           done
//           exit "${missing}"
//
//       - name: Summary
//         env:
//           GH_TOKEN: ${{ github.token }}
//           GH_REPO: ${{ github.repository }}
//         run: |
//           TAG="${{ needs.prepare.outputs.tag }}"
//           {
//             echo "### ${TAG} published"
//             echo
//             gh release view "$TAG" --json assets \
//               --jq '.assets[] | "- \(.name) (\(.size / 1024 / 1024 * 100 | floor / 100) MB)"'
//             echo
//             echo "<${{ github.server_url }}/${{ github.repository }}/releases/tag/${TAG}>"
//           } >> "$GITHUB_STEP_SUMMARY"

// SOURCE: .github/workflows/cut-release.yml

// name: Cut release
//
// # One entry point for releasing. Choose a bump; this verifies the tree is
// # releasable, moves VERSION, propagates it to package.json, the Android
// # manifest, and the Xcode project, opens a changelog section, tags, pushes, and
// # then makes sure a release with artifacts actually exists.
// #
// # Everything below encodes something that went wrong in the sibling repository's
// # pipeline. They are cheap here and expensive to rediscover:
// #
// #   * A tag pushed by a workflow starts nothing. GitHub suppresses triggers from
// #     events raised by GITHUB_TOKEN, so `release.yml` has to be dispatched by
// #     name rather than left to notice the tag.
// #   * Dispatching needs `actions: write`. Without it every dispatch is refused
// #     with "HTTP 403: Resource not accessible by integration".
// #   * `release.yml` takes the tag as a required input on dispatch. Omitting it
// #     fails with "Required input 'tag' not provided".
// #   * A green run is not a release. This job once reported success having
// #     produced nothing at all, so it now ends by checking the release exists
// #     with files attached.
//
// on:
//   workflow_dispatch:
//     inputs:
//       bump:
//         description: "Which part of the version to increase"
//         required: true
//         default: patch
//         type: choice
//         options: [patch, minor, major]
//       dry_run:
//         description: "Work it out and report, but do not tag or push"
//         required: false
//         default: false
//         type: boolean
//
// permissions:
//   # contents: commit the bump and push the tag.
//   # actions: dispatch release.yml. Read access is not enough to start a run.
//   contents: write
//   actions: write
//
// concurrency:
//   group: cut-release
//   cancel-in-progress: false
//
// jobs:
//   cut:
//     name: Cut ${{ inputs.bump }} release
//     runs-on: ubuntu-latest
//     timeout-minutes: 60
//     steps:
//       - uses: actions/checkout@v4
//         with:
//           fetch-depth: 0
//
//       # A release must not be cut from a tree that disagrees with itself.
//       - name: Verify the current version is consistent
//         run: ./scripts/version.sh check
//
//       - name: Work out the next version
//         id: next
//         run: |
//           set -Eeuo pipefail
//           current="$(./scripts/version.sh)"
//           ./scripts/version.sh bump "${{ inputs.bump }}" >/dev/null
//           next="$(./scripts/version.sh)"
//           # Leave the tree alone for now; the real bump happens once the tag has
//           # been checked for collisions.
//           git checkout -- .
//           {
//             echo "current=${current}"
//             echo "next=${next}"
//             echo "tag=v${next}"
//           } >> "$GITHUB_OUTPUT"
//           echo "${current} -> ${next} (v${next})"
//
//       - name: Refuse to reuse a tag
//         run: |
//           if git rev-parse -q --verify "refs/tags/${{ steps.next.outputs.tag }}" >/dev/null; then
//             echo "::error::${{ steps.next.outputs.tag }} already exists."
//             exit 1
//           fi
//           echo "${{ steps.next.outputs.tag }} is free."
//
//       - name: Apply the bump
//         run: |
//           set -Eeuo pipefail
//           ./scripts/version.sh set "${{ steps.next.outputs.next }}"
//           ./scripts/version.sh check
//
//       - name: Open the changelog section
//         run: |
//           python3 - "${{ steps.next.outputs.next }}" <<'PY'
//           import datetime
//           import pathlib
//           import sys
//
//           version = sys.argv[1]
//           path = pathlib.Path("CHANGELOG.md")
//           today = datetime.date.today().isoformat()
//           entry = f"## {version} — {today}\n"
//
//           if not path.exists():
//               path.write_text(
//                   "# Changelog\n\nAll notable changes to this project are documented here.\n\n"
//                   f"## Unreleased\n\n{entry}",
//                   encoding="utf-8",
//               )
//               print(f"Created CHANGELOG.md and opened {version}")
//               raise SystemExit
//
//           text = path.read_text(encoding="utf-8")
//           if "## Unreleased" in text:
//               text = text.replace("## Unreleased", f"## Unreleased\n\n{entry}".rstrip(), 1)
//           else:
//               # No Unreleased heading to promote; insert the section after the title.
//               lines = text.splitlines(keepends=True)
//               at = next((i for i, line in enumerate(lines) if line.startswith("## ")), len(lines))
//               lines.insert(at, f"{entry}\n")
//               text = "".join(lines)
//           path.write_text(text, encoding="utf-8")
//           print(f"Opened {version} — {today}")
//           PY
//
//       - name: Commit, tag and push
//         if: ${{ !inputs.dry_run }}
//         run: |
//           set -Eeuo pipefail
//           git config user.name "github-actions[bot]"
//           git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
//           # Stage by change rather than by name: a named list goes stale the
//           # moment version.sh learns about another file.
//           git add -u
//           git add CHANGELOG.md
//           git commit -m "Release ${{ steps.next.outputs.tag }}
//
//           Version moved from ${{ steps.next.outputs.current }} to ${{ steps.next.outputs.next }}
//           across VERSION, package.json, the Android manifest, and the Xcode
//           project, and the changelog section was opened.
//
//           Cut by the Cut release workflow."
//           git tag -a "${{ steps.next.outputs.tag }}" -m "2048 ${{ steps.next.outputs.next }}"
//           git push origin HEAD:"${GITHUB_REF_NAME}"
//           git push origin "${{ steps.next.outputs.tag }}"
//
//       - name: Start the release build
//         if: ${{ !inputs.dry_run }}
//         env:
//           GH_TOKEN: ${{ github.token }}
//         run: |
//           set -Eeuo pipefail
//           tag="${{ steps.next.outputs.tag }}"
//           # release.yml reads the tag from its input, not from the ref, so it
//           # must be passed explicitly.
//           #
//           # Retried because the tag was pushed seconds ago and the API that
//           # resolves --ref can still answer "No ref found for: <tag>" while it
//           # catches up. That is a timing artefact of this job's own push, not a
//           # problem with the release, and re-running the whole cut to get past
//           # it would mean bumping the version a second time.
//           for attempt in 1 2 3 4 5 6; do
//             if gh workflow run release.yml --ref "${tag}" -f "tag=${tag}"; then
//               echo "dispatched release.yml for ${tag} on attempt ${attempt}"
//               exit 0
//             fi
//             echo "dispatch attempt ${attempt} failed; the tag may not be visible yet"
//             sleep 10
//           done
//           echo "::error::Could not dispatch release.yml for ${tag}."
//           echo "::error::The tag and the bump are pushed. Re-run Release manually with tag=${tag}."
//           exit 1
//
//       - name: Verify a release was actually produced
//         if: ${{ !inputs.dry_run }}
//         env:
//           GH_TOKEN: ${{ github.token }}
//         run: |
//           set -Eeuo pipefail
//           tag="${{ steps.next.outputs.tag }}"
//
//           echo "Waiting for the release build at ${tag}..."
//           runs='[]'
//           deadline=$(( SECONDS + 2400 ))
//           while (( SECONDS < deadline )); do
//             runs="$(gh run list --workflow release.yml --limit 10 \
//               --json status,conclusion,headBranch \
//               --jq "[.[] | select(.headBranch == \"${tag}\")]")"
//             total="$(jq -r 'length' <<< "${runs}")"
//             finished="$(jq -r '[.[] | select(.status == "completed")] | length' <<< "${runs}")"
//             if (( total >= 1 && finished == total )); then
//               break
//             fi
//             sleep 30
//           done
//
//           jq -r '.[] | "  \(.conclusion // .status)"' <<< "${runs}"
//           if [[ "$(jq -r '[.[] | select(.conclusion != "success")] | length' <<< "${runs}")" != "0" ]]; then
//             echo "::error::The release build did not succeed at ${tag}."
//             exit 1
//           fi
//
//           # Builds passing and a release existing are different claims.
//           if ! gh release view "${tag}" >/dev/null 2>&1; then
//             echo "::error::No GitHub Release exists for ${tag}, despite the build succeeding."
//             exit 1
//           fi
//           assets="$(gh release view "${tag}" --json assets --jq '.assets | length')"
//           if [[ "${assets}" -lt 3 ]]; then
//             echo "::error::Release ${tag} has ${assets} file(s); expected the Android, iOS and web artifacts."
//             gh release view "${tag}" --json assets --jq '.assets[].name'
//             exit 1
//           fi
//           echo "Release ${tag} is published with ${assets} file(s):"
//           gh release view "${tag}" --json assets --jq '.assets[] | "  \(.name)"'
//
//       - name: Summary
//         run: |
//           {
//             echo "### ${{ steps.next.outputs.tag }}"
//             echo
//             echo "| | |"
//             echo "| --- | --- |"
//             echo "| From | ${{ steps.next.outputs.current }} |"
//             echo "| To | ${{ steps.next.outputs.next }} |"
//             echo "| Bump | ${{ inputs.bump }} |"
//             echo "| Dry run | ${{ inputs.dry_run }} |"
//             echo
//             if [ "${{ inputs.dry_run }}" = "true" ]; then
//               echo "Nothing was pushed. Rerun with dry run off to cut it."
//             else
//               echo "Tagged, built, and verified published with artifacts."
//             fi
//           } >> "$GITHUB_STEP_SUMMARY"

// SOURCE: .github/release.yml

// changelog:
//   exclude:
//     labels: [skip-changelog]
//   categories:
//     - title: New features
//       labels: [enhancement]
//     - title: Fixes
//       labels: [bug]
//     - title: Documentation and tooling
//       labels: [documentation, developer-experience]
//     - title: Other changes
//       labels: ["*"]

// SOURCE: CHANGELOG.md

// # Changelog
//
// All notable changes to this project are documented here.
//
// The version applies to all three clients at once: the web app, the iOS app, and
// the Android app ship from one `VERSION` file, so a release number means the same
// thing everywhere. See [docs/releasing.md](docs/releasing.md).
//
// ## Unreleased
//
// ## 2.1.0 — 2026-09-19
//
// Optional Cloud API and client accounts. Play stays local-first; an account adds
// cross-device save sync, scores, and leaderboards. Express + MongoDB Atlas backend
// with OpenAPI 3.1 (Swagger UI, Redoc, Scalar), wired into web, iOS, and Android.
// See [docs/backend.md](docs/backend.md) and [docs/privacy.md](docs/privacy.md).
//
// ## 2.0.1 — 2026-09-05
//
// ## 2.0.0 — 2026-09-02
//
// Cross-platform rebuild. The web client, the SwiftUI iOS app, and the Jetpack
// Compose Android app all implement the same behavioural contract — identical move,
// merge, scoring, undo, win, and game-over rules — with shared documentation, a
// `make`-driven workflow, and per-client test suites.
//
// ## 1.1.0 — 2025-06-30
//
// Web client with persistent best score, undo, keyboard and touch input, and the
// About page.
