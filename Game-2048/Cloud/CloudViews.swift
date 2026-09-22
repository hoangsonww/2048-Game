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
        .accessibilityLabel(cloud.isSignedIn ? "Account: \(cloud.user?.displayName ?? "")" : "Sign in")
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
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guestPrompt")
    }
}

enum AuthMode: String, Identifiable {
    case register, login
    var id: String { rawValue }
}

/// Shared chrome for credential sheets: paper, not a Settings grouped list.
///
/// `Form` draws inset grouped cards with hairline separators, so Sign in sat
/// in a white list next to Create an account and Forgot your password. The
/// game already has a palette and a card language; the sheets now use that.
private struct CloudFormScaffold<Content: View>: View {
    let dismissTitle: String
    let dismissIdentifier: String
    let onDismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .center, spacing: 16) {
                    content
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 32)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .background(CloudPalette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(dismissTitle, action: onDismiss)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CloudPalette.ink)
                        .accessibilityIdentifier(dismissIdentifier)
                }
            }
        }
        .tint(CloudPalette.accent)
    }
}

/// A labelled input that matches the game's score-card chrome.
private struct CloudField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .center, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CloudPalette.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)
            content
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(CloudPalette.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.black.opacity(0.08))
                )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct CloudTextField: View {
    let title: String
    @Binding var text: String
    var textContentType: UITextContentType
    var keyboardType: UIKeyboardType = .default
    var identifier: String

    var body: some View {
        CloudField(title: title) {
            TextField("", text: $text, prompt: Text(title).foregroundStyle(CloudPalette.muted.opacity(0.55)))
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(title)
        }
    }
}

/// The coral fill that Form never gave the primary action.
private struct CloudSubmitButton: View {
    enum Style {
        case accent, ink
        var fill: Color {
            switch self {
            case .accent: return CloudPalette.accent
            case .ink: return CloudPalette.ink
            }
        }
    }

    let title: String
    let busyTitle: String
    let busy: Bool
    let identifier: String
    var style: Style = .accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(busy ? busyTitle : title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                style.fill.opacity(busy ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier(identifier)
    }
}

private struct CloudLinkButton: View {
    let title: String
    let identifier: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .underline(pattern: .solid, color: CloudPalette.muted.opacity(0.45))
                .foregroundStyle(CloudPalette.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }
}

private struct CloudFormIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(CloudPalette.accent)
            .frame(width: 48, height: 48)
            .background(
                CloudPalette.accent.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
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
        CloudField(title: title) {
            HStack(spacing: 8) {
                Group {
                    if revealed {
                        TextField("", text: $text, prompt: Text(title).foregroundStyle(CloudPalette.muted.opacity(0.55)))
                            .textContentType(textContentType)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier(identifier)
                            .accessibilityLabel(title)
                    } else {
                        SecureField("", text: $text, prompt: Text(title).foregroundStyle(CloudPalette.muted.opacity(0.55)))
                            .textContentType(textContentType)
                            .focused($focused)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier(identifier)
                            .accessibilityLabel(title)
                    }
                }
                .textFieldStyle(.plain)

                Button {
                    revealed.toggle()
                    focused = true
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(CloudPalette.muted)
                .accessibilityLabel(revealed ? "Hide \(title.lowercased())" : "Show \(title.lowercased())")
                .accessibilityIdentifier("\(identifier)Reveal")
            }
        }
    }
}

/// A credential error that stays on screen while the fields scroll.
///
/// Kept outside the scrolling stack so a mismatch (or a server refusal) is
/// visible the moment it appears, even if the keyboard has pushed the
/// password fields off the bottom.
private struct AuthCallout: View {
    let message: String
    let identifier: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(CloudPalette.accent)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                CloudPalette.accent.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .accessibilityIdentifier(identifier)
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

    private var busy: Bool { cloud.activity == .authenticating }

    var body: some View {
        CloudFormScaffold(
            dismissTitle: "Not now",
            dismissIdentifier: "authDismiss",
            onDismiss: { dismiss() }
        ) {
            if mismatch && passwordsDisagree {
                AuthCallout(message: "Those passwords do not match.", identifier: "passwordMismatch")
            }

            CloudFormIcon(systemName: registering ? "person.badge.plus" : "person.crop.circle")

            Text(registering ? "Create your account" : "Welcome back")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .tracking(-1.1)
                .foregroundStyle(CloudPalette.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("authTitle")

            Text(intro)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(CloudPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("authIntro")

            if let error = cloud.authError {
                AuthCallout(message: error, identifier: "authError")
            }

            Group {
                if registering {
                    CloudTextField(
                        title: "Username",
                        text: $username,
                        textContentType: .username,
                        identifier: "usernameField"
                    )
                    CloudTextField(
                        title: "Email",
                        text: $email,
                        textContentType: .emailAddress,
                        keyboardType: .emailAddress,
                        identifier: "emailField"
                    )
                } else {
                    CloudTextField(
                        title: "Username or email",
                        text: $identifier,
                        textContentType: .username,
                        identifier: "identifierField"
                    )
                }

                RevealablePasswordField(
                    title: "Password",
                    text: $password,
                    textContentType: registering ? .newPassword : .password,
                    identifier: "passwordField"
                )
                .id(mode)

                if registering {
                    RevealablePasswordField(
                        title: "Confirm password",
                        text: $confirmPassword,
                        identifier: "confirmPasswordField"
                    )
                }
            }
            .disabled(busy)

            Text("At least 8 characters, including one letter and one number.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(CloudPalette.muted.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            CloudSubmitButton(
                title: registering ? "Create account" : "Sign in",
                busyTitle: registering ? "Creating account…" : "Signing in…",
                busy: busy,
                identifier: "authSubmit",
                action: {
                    // Nothing to lose, nothing to ask. A played round is
                    // warned about before it leaves the screen.
                    attempt()
                }
            )
            .padding(.top, 4)

            VStack(spacing: 4) {
                CloudLinkButton(
                    title: registering ? "I already have an account" : "Create an account instead",
                    identifier: "authSwitch",
                    disabled: busy
                ) {
                    cloud.clearAuthError()
                    mismatch = false
                    confirmPassword = ""
                    mode = registering ? .login : .register
                }

                CloudLinkButton(
                    title: "Forgot your password?",
                    identifier: "authForgot",
                    disabled: busy
                ) {
                    cloud.clearAuthError()
                    onForgotPassword()
                }
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
        CloudFormScaffold(
            dismissTitle: "Back to sign in",
            dismissIdentifier: "resetDismiss",
            onDismiss: { dismiss() }
        ) {
            if mismatch && passwordsDisagree {
                AuthCallout(message: "Those passwords do not match.", identifier: "resetMismatch")
            }

            CloudFormIcon(systemName: "lock.fill")

            Text("Reset your password")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .tracking(-1.1)
                .foregroundStyle(CloudPalette.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("resetTitle")

            Text("Confirm the username and email on the account, then choose a new password. Every device signed in to it will be signed out.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(CloudPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("resetIntro")

            if let error = cloud.authError {
                AuthCallout(message: error, identifier: "resetError")
            }

            Group {
                CloudTextField(
                    title: "Username",
                    text: $username,
                    textContentType: .username,
                    identifier: "resetUsernameField"
                )
                CloudTextField(
                    title: "Email",
                    text: $email,
                    textContentType: .emailAddress,
                    keyboardType: .emailAddress,
                    identifier: "resetEmailField"
                )
                RevealablePasswordField(title: "New password", text: $password, identifier: "resetPasswordField")
                RevealablePasswordField(title: "Confirm new password", text: $confirmPassword, identifier: "resetConfirmField")
            }
            .disabled(working)

            Text("At least 8 characters, including one letter and one number.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(CloudPalette.muted.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            CloudSubmitButton(
                title: "Reset password",
                busyTitle: "Resetting…",
                busy: working,
                identifier: "resetSubmit"
            ) {
                guard passwordsDisagree == false else {
                    mismatch = true
                    return
                }
                mismatch = false
                onReset(username, email, password)
            }
            .padding(.top, 4)
        }
    }
}

struct AccountSheet: View {
    @ObservedObject var cloud: CloudController
    let onSyncNow: () -> Void
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var syncing: Bool { cloud.activity == .syncing }
    private var signingOut: Bool { cloud.activity == .signingOut }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .center, spacing: 18) {
                    if let user = cloud.user {
                        CloudFormIcon(systemName: "person.crop.circle.fill")

                        Text(user.displayName)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .tracking(-1.1)
                            .foregroundStyle(CloudPalette.ink)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        Text(user.email)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(CloudPalette.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        // Career totals come from the account and from nowhere
                        // else. A guest round played on this device before
                        // signing in is not part of this account's history.
                        VStack(spacing: 0) {
                            AccountStatRow(label: "Best score", value: user.statistics.bestScore.formatted())
                            AccountStatDivider()
                            AccountStatRow(label: "Rounds played", value: user.statistics.gamesPlayed.formatted())
                            AccountStatDivider()
                            AccountStatRow(label: "Rounds won", value: user.statistics.gamesWon.formatted())
                            AccountStatDivider()
                            AccountStatRow(label: "Highest tile", value: user.statistics.highestTile.formatted())
                        }
                        .padding(.vertical, 6)
                        .background(
                            Color.white.opacity(0.78),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.08))
                        )
                        .accessibilityElement(children: .contain)

                        Text(cloud.status)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CloudPalette.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("accountSyncStatus")

                        CloudSubmitButton(
                            title: "Sync now",
                            busyTitle: "Syncing…",
                            busy: syncing,
                            identifier: "syncNowButton",
                            style: .ink,
                            action: onSyncNow
                        )
                        .padding(.top, 2)

                        Text("Signing out brings back the round this device was playing before you signed in. Your account keeps its own.")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(CloudPalette.muted.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)

                        CloudLinkButton(
                            title: signingOut ? "Signing out…" : "Sign out",
                            identifier: "signOutButton",
                            disabled: signingOut,
                            action: onSignOut
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 32)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(CloudPalette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CloudPalette.ink)
                        .accessibilityIdentifier("accountDismiss")
                }
            }
        }
        .tint(CloudPalette.accent)
    }
}

private struct AccountStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CloudPalette.ink)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(CloudPalette.muted)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

private struct AccountStatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 16)
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
                Text("Leaderboard")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .tracking(-1.1)
                    .foregroundStyle(CloudPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    ForEach(periods, id: \.0) { key, label in
                        let active = cloud.leaderboardPeriod == key
                        Button {
                            onPeriod(key)
                        } label: {
                            Text(label)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(active ? Color.white : CloudPalette.muted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    (active ? CloudPalette.ink : Color.white.opacity(0.7)),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule().stroke(Color.black.opacity(active ? 0 : 0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(cloud.activity == .loadingLeaderboard)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("leaderboardPeriods")

                if cloud.activity == .loadingLeaderboard && (cloud.leaderboard?.entries.isEmpty ?? true) {
                    ProgressView("Loading…")
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(cloud.leaderboard?.entries ?? []) { entry in
                            HStack(spacing: 12) {
                                Text("#\(entry.rank)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(CloudPalette.muted)
                                    .frame(width: 38, alignment: .leading)
                                Text(entry.displayName)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(CloudPalette.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(entry.highestTile.formatted())
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(CloudPalette.muted)
                                Text(entry.score.formatted())
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundStyle(CloudPalette.ink)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                entry.isViewer
                                    ? CloudPalette.accent.opacity(0.14)
                                    : Color.white.opacity(0.72),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.black.opacity(0.06))
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Rank \(entry.rank), \(entry.displayName), \(entry.score) points")
                        }

                        Text(cloud.leaderboardNote)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(CloudPalette.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                            .accessibilityIdentifier("leaderboardNote")
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                }
            }
            .background(CloudPalette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CloudPalette.ink)
                }
            }
        }
        .tint(CloudPalette.accent)
    }
}
