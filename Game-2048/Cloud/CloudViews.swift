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
struct AccountButton: View {
    @ObservedObject var cloud: CloudController
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: cloud.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(cloud.user?.displayName ?? "Sign in")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .frame(maxWidth: 88)
            }
            .padding(.horizontal, 11)
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
/// points of slack and spending them here would send the board into a
/// `ScrollView`.
struct CloudBar: View {
    @ObservedObject var cloud: CloudController
    let onCreateAccount: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if cloud.showGuestPrompt {
                Button(action: onCreateAccount) {
                    HStack(spacing: 6) {
                        Image(systemName: "icloud.and.arrow.up").font(.system(size: 12, weight: .semibold))
                        Text("Save your progress on every device")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }
                .foregroundStyle(CloudPalette.accent)
                .accessibilityIdentifier("guestPrompt")

                Button {
                    cloud.dismissPrompt()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(CloudPalette.muted)
                .accessibilityLabel("Dismiss this suggestion")
                .accessibilityIdentifier("dismissGuestPrompt")
            } else {
                if cloud.phase == .working {
                    ProgressView().controlSize(.mini)
                }
                Text(cloud.status)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CloudPalette.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("cloudStatus")
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: cloud.showGuestPrompt)
    }
}

enum AuthMode: String, Identifiable {
    case register, login
    var id: String { rawValue }
}

/// Sign-up and sign-in in one sheet.
///
/// Two sheets would double the surface for one decision a player makes once;
/// swapping the fields keeps the flow to a single place they can change their
/// mind inside.
struct AuthSheet: View {
    @ObservedObject var cloud: CloudController
    @State var mode: AuthMode
    let onRegister: (String, String, String) -> Void
    let onLogin: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var email = ""
    @State private var identifier = ""
    @State private var password = ""

    private var registering: Bool { mode == .register }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(registering
                         ? "Keep your board, best score, and streak on every device you play on."
                         : "Sign in to pick up the round you left on another device.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(CloudPalette.muted)
                        .listRowBackground(Color.clear)
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
                            .accessibilityIdentifier("usernameField")
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("emailField")
                    } else {
                        TextField("Username or email", text: $identifier)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("identifierField")
                    }
                    SecureField("Password", text: $password)
                        .textContentType(registering ? .newPassword : .password)
                        .accessibilityIdentifier("passwordField")
                } footer: {
                    Text("At least 8 characters, including one letter and one number.")
                }

                Section {
                    Button {
                        if registering { onRegister(username, email, password) } else { onLogin(identifier, password) }
                    } label: {
                        HStack {
                            Spacer()
                            Text(registering ? "Create account" : "Sign in").font(.system(size: 16, weight: .bold, design: .rounded))
                            Spacer()
                        }
                    }
                    .disabled(cloud.phase == .working)
                    .accessibilityIdentifier("authSubmit")

                    Button(registering ? "I already have an account" : "Create an account instead") {
                        cloud.clearAuthError()
                        mode = registering ? .login : .register
                    }
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(CloudPalette.muted)
                    .accessibilityIdentifier("authSwitch")
                }
            }
            .navigationTitle(registering ? "Create your account" : "Welcome back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            // Once the controller reports a signed-in session the sheet has
            // done its job; leaving it up would make a player dismiss a form
            // that succeeded.
            .onChange(of: cloud.isSignedIn) { _, signedIn in if signedIn { dismiss() } }
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
                    Button("Sync now", action: onSyncNow).accessibilityIdentifier("syncNowButton")
                }

                Section {
                    Button("Sign out", role: .destructive, action: onSignOut).accessibilityIdentifier("signOutButton")
                } footer: {
                    Text("Signing out leaves this round on the device. Nothing is deleted.")
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
                .accessibilityIdentifier("leaderboardPeriods")

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
