import SwiftUI

/// The account, sync, and leaderboard surface for the SwiftUI client.
///
/// Every view here is additive, and — importantly — costs the main screen no
/// vertical space. The board must not end up inside a scrolling container: a
/// `ScrollView` pan is a UIKit recogniser and beats the board's `DragGesture`
/// outright, which is the bug documented at length in `GameView`. So the
/// account controls live in the header, the status and the invitation share
/// the single hint line that was already there, and everything else is a
/// sheet.
///
/// Colours come from the shared design tokens; see ARCHITECTURE.md,
/// "Design tokens, shared by hand".

enum CloudPalette {
    static let paper = Color(red: 0.961, green: 0.941, blue: 0.902)
    static let ink = Color(red: 0.141, green: 0.137, blue: 0.122)
    static let accent = Color(red: 0.914, green: 0.388, blue: 0.271)
    static let muted = Color(red: 0.435, green: 0.416, blue: 0.380)
}

/// The header's account control: a name when signed in, an invitation when not.
///
/// The label is capped rather than fixed. A `frame(maxWidth:)` reserves its
/// width whatever is in it, so "Sign in" sat in the middle of a pill sized for
/// a long display name, with a gap either side of it that looked like a
/// mistake. Capping lets the control hug two words and still truncate a name.
struct AccountButton: View {
    @ObservedObject var cloud: CloudController
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: cloud.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(cloud.user?.displayName ?? "Sign in")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 92, alignment: .leading)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.white.opacity(0.65), in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.08)))
        }
        .foregroundStyle(CloudPalette.ink)
        .accessibilityLabel(cloud.isSignedIn ? "Account: \(cloud.user?.displayName ?? "")" : "Sign in or create an account")
        .accessibilityIdentifier("accountButton")
    }
}

struct LeaderboardButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.black.opacity(0.08)))
        }
        .foregroundStyle(CloudPalette.ink)
        .accessibilityLabel("Leaderboard")
        .accessibilityIdentifier("leaderboardButton")
    }
}

/// The single line under the board.
///
/// It is an invitation while the player is a guest and a sync status once they
/// are not — one row either way, because the layout has roughly thirteen
/// Sync status under the board. The guest invite is a floating toast elsewhere
/// so it never steals vertical space from the game.
struct CloudBar: View {
    @ObservedObject var cloud: CloudController

    var body: some View {
        HStack(spacing: 8) {
            if cloud.isBusy && cloud.activity != .loadingLeaderboard {
                ProgressView().controlSize(.mini)
            }
            // Quiet enough to read as a footnote to the board rather than a
            // label crammed against the action bar.
            Text(cloud.status)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(CloudPalette.muted.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("cloudStatus")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .animation(.easeInOut(duration: 0.2), value: cloud.status)
    }
}

/// Temporary guest invite — overlays the screen briefly on launch, then hides.
struct GuestToast: View {
    let onCreateAccount: () -> Void
    let onSignIn: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playing as a guest")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(CloudPalette.ink)
                    Text("Create a free account to keep your board and best score on every device.")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(CloudPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(CloudPalette.muted)
                .accessibilityLabel("Dismiss this suggestion")
                .accessibilityIdentifier("dismissGuestPrompt")
            }
            HStack(spacing: 8) {
                Button(action: onCreateAccount) {
                    Text("Create account")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(CloudPalette.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("guestPromptCreate")
                Button("Sign in", action: onSignIn)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CloudPalette.ink)
                    .accessibilityIdentifier("guestPromptSignIn")
            }
        }
        .padding(14)
        .frame(maxWidth: 360)
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(CloudPalette.accent)
                .frame(width: 3)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guestPrompt")
    }
}

enum AuthMode: String, Identifiable {
    case register, login
    var id: String { rawValue }
}

/**
 A password field the player can read back.

 SwiftUI has no revealable secure field, and the usual trick — leaving a
 `SecureField` and a `TextField` both in the hierarchy — loses the keyboard
 and the cursor every time it flips. Swapping which one exists keeps focus,
 and the eye control carries its own accessibility label so a screen reader
 announces the state rather than the icon.
 */
struct RevealablePasswordField: View {
    let title: String
    @Binding var text: String
    var textContentType: UITextContentType = .newPassword
    var identifier: String

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField(title, text: $text)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .accessibilityIdentifier(identifier)
                } else {
                    SecureField(title, text: $text)
                        .textContentType(textContentType)
                        .focused($focused)
                        .accessibilityIdentifier(identifier)
                }
            }

            Button {
                revealed.toggle()
                focused = true
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(CloudPalette.muted)
            .accessibilityLabel(revealed ? "Hide \(title.lowercased())" : "Show \(title.lowercased())")
            .accessibilityIdentifier("\(identifier)Reveal")
        }
    }
}

/// Sign-up and sign-in in one sheet.
///
/// Two sheets would double the surface for one decision a player makes once;
/// swapping the fields keeps the flow to a single place they can change their
/// mind inside.
struct AuthSheet: View {
    @ObservedObject var cloud: CloudController
    @State var mode: AuthMode
    /// Whether a round is on screen that signing in will take off it.
    var handsOverRound: Bool = false
    let onRegister: (String, String, String) -> Void
    let onLogin: (String, String) -> Void
    var onForgotPassword: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var email = ""
    @State private var identifier = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var mismatch = false
    @State private var confirmingHandover = false

    private var registering: Bool { mode == .register }

    private var intro: String {
        if handsOverRound {
            return registering
                ? "Your account starts on a clean board. This round stays saved on this device and comes back when you sign out."
                : "Signing in loads the round saved to your account. This round stays on this device and comes back when you sign out."
        }
        return registering
            ? "Keep your board, best score, and streak on every device you play on."
            : "Sign in to pick up the round you left on another device."
    }

    /// Whether the two new-password fields disagree. Sign-in has nothing to
    /// confirm: a mistyped password there is reported by the server at once.
    private var passwordsDisagree: Bool { registering && password != confirmPassword }

    private func attempt() {
        guard passwordsDisagree == false else {
            mismatch = true
            return
        }
        mismatch = false
        if handsOverRound { confirmingHandover = true } else { submit() }
    }

    private func submit() {
        if registering { onRegister(username, email, password) } else { onLogin(identifier, password) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(intro)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(CloudPalette.muted)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("authIntro")
                }

                if let error = cloud.authError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(CloudPalette.accent)
                            .accessibilityIdentifier("authError")
                    }
                }

                Section {
                    if registering {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(cloud.activity == .authenticating)
                            .accessibilityIdentifier("usernameField")
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(cloud.activity == .authenticating)
                            .accessibilityIdentifier("emailField")
                    } else {
                        TextField("Username or email", text: $identifier)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(cloud.activity == .authenticating)
                            .accessibilityIdentifier("identifierField")
                    }
                    RevealablePasswordField(
                        title: "Password",
                        text: $password,
                        textContentType: registering ? .newPassword : .password,
                        identifier: "passwordField"
                    )
                    .disabled(cloud.activity == .authenticating)

                    if registering {
                        RevealablePasswordField(
                            title: "Confirm password",
                            text: $confirmPassword,
                            identifier: "confirmPasswordField"
                        )
                        .disabled(cloud.activity == .authenticating)
                    }
                } footer: {
                    if mismatch && passwordsDisagree {
                        Text("Those passwords do not match.")
                            .foregroundStyle(CloudPalette.accent)
                            .accessibilityIdentifier("passwordMismatch")
                    } else {
                        Text("At least 8 characters, including one letter and one number.")
                    }
                }

                Section {
                    Button {
                        // Nothing to lose, nothing to ask. A played round is
                        // warned about before it leaves the screen.
                        attempt()
                    } label: {
                        HStack(spacing: 8) {
                            if cloud.activity == .authenticating {
                                ProgressView().controlSize(.small)
                            }
                            Text(cloud.activity == .authenticating
                                 ? (registering ? "Creating account…" : "Signing in…")
                                 : (registering ? "Create account" : "Sign in"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(cloud.activity == .authenticating)
                    .accessibilityIdentifier("authSubmit")

                    Button(registering ? "I already have an account" : "Create an account instead") {
                        cloud.clearAuthError()
                        mismatch = false
                        confirmPassword = ""
                        mode = registering ? .login : .register
                    }
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(CloudPalette.muted)
                    .disabled(cloud.activity == .authenticating)
                    .accessibilityIdentifier("authSwitch")

                    Button("Forgot your password?") {
                        cloud.clearAuthError()
                        onForgotPassword()
                    }
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(CloudPalette.muted)
                    .disabled(cloud.activity == .authenticating)
                    .accessibilityIdentifier("authForgot")
                }
            }
            .navigationTitle(registering ? "Create your account" : "Welcome back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .accessibilityIdentifier("authDismiss")
                }
            }
            // An alert rather than a confirmation dialog: this is presented
            // from inside a sheet, and only an alert reliably puts its buttons
            // in the accessibility tree from there — which is also what the UI
            // test needs in order to prove the warning can be declined.
            .alert("Set this round aside?", isPresented: $confirmingHandover) {
                Button("Keep playing", role: .cancel) { confirmingHandover = false }
                Button("Continue") { submit() }
            } message: {
                Text(registering
                     ? "Your new account starts on a clean board. This round stays saved on this device and comes back the moment you sign out."
                     : "Your account keeps its own board. This round stays saved on this device and comes back the moment you sign out.")
            }
            // Once the controller reports a signed-in session the sheet has
            // done its job; leaving it up would make a player dismiss a form
            // that succeeded.
            .onChange(of: cloud.isSignedIn) { _, signedIn in if signedIn { dismiss() } }
        }
    }
}

/**
 Password reset, without an email round trip.

 Confirming the username and the address on the account is the whole proof —
 see the security note on the endpoint in `server/src/routes/auth.routes.js`.
 The sheet says plainly that every device will be signed out, because that is
 what happens and a player should not discover it afterwards.
 */
struct ResetPasswordSheet: View {
    @ObservedObject var cloud: CloudController
    let onReset: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var mismatch = false

    private var working: Bool { cloud.activity == .authenticating }
    private var passwordsDisagree: Bool { password != confirmPassword }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Confirm the username and email on the account, then choose a new password. Every device signed in to it will be signed out.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(CloudPalette.muted)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("resetIntro")
                }

                if let error = cloud.authError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(CloudPalette.accent)
                            .accessibilityIdentifier("resetError")
                    }
                }

                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(working)
                        .accessibilityIdentifier("resetUsernameField")
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(working)
                        .accessibilityIdentifier("resetEmailField")
                    RevealablePasswordField(title: "New password", text: $password, identifier: "resetPasswordField")
                        .disabled(working)
                    RevealablePasswordField(title: "Confirm new password", text: $confirmPassword, identifier: "resetConfirmField")
                        .disabled(working)
                } footer: {
                    if mismatch && passwordsDisagree {
                        Text("Those passwords do not match.")
                            .foregroundStyle(CloudPalette.accent)
                            .accessibilityIdentifier("resetMismatch")
                    } else {
                        Text("At least 8 characters, including one letter and one number.")
                    }
                }

                Section {
                    Button {
                        guard passwordsDisagree == false else {
                            mismatch = true
                            return
                        }
                        mismatch = false
                        onReset(username, email, password)
                    } label: {
                        HStack(spacing: 8) {
                            if working { ProgressView().controlSize(.small) }
                            Text(working ? "Resetting…" : "Reset password")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(working)
                    .accessibilityIdentifier("resetSubmit")
                }
            }
            .navigationTitle("Reset your password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back to sign in") { dismiss() }
                        .accessibilityIdentifier("resetDismiss")
                }
            }
        }
    }
}

struct AccountSheet: View {
    @ObservedObject var cloud: CloudController
    let onSyncNow: () -> Void
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let user = cloud.user {
                    Section {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(user.displayName).font(.system(size: 22, weight: .heavy, design: .rounded)).tracking(-0.8)
                            Text(user.email).font(.system(size: 13, design: .rounded)).foregroundStyle(CloudPalette.muted)
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Career") {
                        LabeledContent("Best score", value: user.statistics.bestScore.formatted())
                        LabeledContent("Rounds played", value: user.statistics.gamesPlayed.formatted())
                        LabeledContent("Rounds won", value: user.statistics.gamesWon.formatted())
                        LabeledContent("Highest tile", value: user.statistics.highestTile.formatted())
                    }
                }

                Section("Sync") {
                    Text(cloud.status).font(.system(size: 13, design: .rounded)).foregroundStyle(CloudPalette.muted)
                    Button {
                        onSyncNow()
                    } label: {
                        HStack(spacing: 8) {
                            if cloud.activity == .syncing {
                                ProgressView().controlSize(.small)
                            }
                            Text(cloud.activity == .syncing ? "Syncing…" : "Sync now")
                        }
                    }
                    .disabled(cloud.activity == .syncing)
                    .accessibilityIdentifier("syncNowButton")
                }

                Section {
                    Button(role: .destructive) {
                        onSignOut()
                    } label: {
                        HStack(spacing: 8) {
                            if cloud.activity == .signingOut {
                                ProgressView().controlSize(.small)
                            }
                            Text(cloud.activity == .signingOut ? "Signing out…" : "Sign out")
                        }
                    }
                    .disabled(cloud.activity == .signingOut)
                    .accessibilityIdentifier("signOutButton")
                } footer: {
                    Text("Signing out brings back the round this device was playing before you signed in. Your account keeps its own.")
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct LeaderboardSheet: View {
    @ObservedObject var cloud: CloudController
    let onPeriod: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let periods = [("daily", "Today"), ("weekly", "This week"), ("all", "All time")]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Window", selection: Binding(
                    get: { cloud.leaderboardPeriod },
                    set: { onPeriod($0) }
                )) {
                    ForEach(periods, id: \.0) { key, label in Text(label).tag(key) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .disabled(cloud.activity == .loadingLeaderboard)
                .accessibilityIdentifier("leaderboardPeriods")

                if cloud.activity == .loadingLeaderboard && (cloud.leaderboard?.entries.isEmpty ?? true) {
                    ProgressView("Loading…")
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity)
                }

                List {
                    ForEach(cloud.leaderboard?.entries ?? []) { entry in
                        HStack(spacing: 12) {
                            Text("#\(entry.rank)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(CloudPalette.muted)
                                .frame(width: 38, alignment: .leading)
                            Text(entry.displayName)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Spacer()
                            Text(entry.highestTile.formatted())
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(CloudPalette.muted)
                            Text(entry.score.formatted())
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                        }
                        .listRowBackground(entry.isViewer ? CloudPalette.accent.opacity(0.13) : Color.clear)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Rank \(entry.rank), \(entry.displayName), \(entry.score) points")
                    }

                    Section {
                        Text(cloud.leaderboardNote)
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(CloudPalette.muted)
                            .accessibilityIdentifier("leaderboardNote")
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
