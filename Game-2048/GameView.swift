import SwiftUI
import UIKit

struct GameView: View {
    @StateObject private var viewModel: GameViewModel
    @StateObject private var cloud: CloudController
    @StateObject private var sounds = GameSounds.shared
    @State private var showingHelp = false
    @State private var confirmingNewGame = false
    @State private var showingWin = false
    @State private var authMode: AuthMode?
    @State private var showingAccount = false
    @State private var showingLeaderboard = false
    @State private var showingReset = false
    @State private var showGuestToast = false

    private let paper = Color(red: 0.961, green: 0.941, blue: 0.902)
    private let ink = Color(red: 0.141, green: 0.137, blue: 0.122)
    private let accent = Color(red: 0.914, green: 0.388, blue: 0.271)
    private let muted = Color(red: 0.435, green: 0.416, blue: 0.380)

    @MainActor
    init(viewModel: GameViewModel = GameViewModel(), cloud: CloudController? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _cloud = StateObject(wrappedValue: cloud ?? CloudController.live())
        _showingWin = State(initialValue: viewModel.hasWon)
    }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            Canvas { context, size in
                let spacing: CGFloat = 44
                var path = Path()
                stride(from: 0, through: size.width, by: spacing).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                stride(from: 0, through: size.height, by: spacing).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                context.stroke(path, with: .color(Color(red: 0.72, green: 0.68, blue: 0.61).opacity(0.10)), lineWidth: 0.6)
            }
            .ignoresSafeArea()

            // The board must not sit inside a scrolling container. A ScrollView
            // pan is a UIKit gesture recogniser, so it beats the board's SwiftUI
            // DragGesture outright: every vertical swipe scrolled the page and
            // never reached the game, which measured as the whole screen
            // shifting 13pt with no move registered. `.highPriorityGesture` and
            // `.scrollBounceBehavior` both fail to change that, because the
            // content genuinely overflowed and the recogniser genuinely won.
            //
            // The layout does not need to scroll: the board already sizes with
            // `.aspectRatio(1, contentMode: .fit)`, so given a fixed height it
            // absorbs the difference instead of overflowing. ViewThatFits keeps
            // a scrolling fallback for the cases that truly cannot fit — very
            // small devices, or the largest accessibility text sizes — where
            // being able to reach the controls matters more than swipe purity.
            ViewThatFits(in: .vertical) {
                content
                ScrollView {
                    content
                }
                .scrollIndicators(.hidden)
            }

            if showGuestToast {
                VStack {
                    Spacer()
                    GuestToast(
                        onCreateAccount: { authMode = .register },
                        onSignIn: { authMode = .login },
                        onDismiss: {
                            cloud.dismissPrompt()
                            showGuestToast = false
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // Only the card receives taps — the Spacer must not steal board
                    // swipes or the Undo / New game buttons underneath.
                    .allowsHitTesting(true)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showGuestToast)
        .task {
            // UI tests drive the board themselves; the invite toast would eat
            // swipes and button taps for the first few seconds of every case.
            guard ProcessInfo.processInfo.environment["GAME2048_UI_TESTING"] != "1" else { return }
            guard cloud.showGuestPrompt else { return }
            showGuestToast = true
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            showGuestToast = false
        }
        .onChange(of: cloud.isSignedIn) { _, signedIn in
            if signedIn { showGuestToast = false }
        }
        .sheet(isPresented: $showingHelp) { HelpView() }
        .sheet(item: $authMode) { mode in
            AuthSheet(
                cloud: cloud,
                mode: mode,
                // The board on screen belongs to this device, not to the
                // account about to sign in. Say so before it leaves.
                handsOverRound: viewModel.hasProgress,
                onRegister: { username, email, password in
                    Task {
                        guard await cloud.register(username: username, email: email, password: password) else { return }
                        await adoptAccount()
                    }
                },
                onLogin: { identifier, password in
                    Task {
                        guard await cloud.login(identifier: identifier, password: password) else { return }
                        await adoptAccount()
                    }
                },
                onForgotPassword: {
                    authMode = nil
                    showingReset = true
                }
            )
        }
        .sheet(isPresented: $showingReset) {
            ResetPasswordSheet(cloud: cloud) { username, email, newPassword in
                Task {
                    guard await cloud.resetPassword(username: username, email: email, newPassword: newPassword) else { return }
                    // Every session was revoked, this one included, so the
                    // device goes back to the round it owns.
                    viewModel.endAccountSession()
                    showingReset = false
                    authMode = .login
                }
            }
        }
        .sheet(isPresented: $showingAccount) {
            AccountSheet(
                cloud: cloud,
                onSyncNow: { Task { await cloud.syncNow(save: viewModel.cloudSave, apply: { _ = viewModel.applyCloudSave($0) }) } },
                onSignOut: {
                    Task {
                        await cloud.signOut()
                        // Back to the round this device was playing before the
                        // session started — board, score, and best score.
                        viewModel.endAccountSession()
                        showingAccount = false
                    }
                }
            )
        }
        .sheet(isPresented: $showingLeaderboard) {
            LeaderboardSheet(cloud: cloud, onPeriod: { period in Task { await cloud.loadLeaderboard(period: period) } })
                .task { await cloud.loadLeaderboard() }
        }
        .confirmationDialog("Start a fresh board?", isPresented: $confirmingNewGame, titleVisibility: .visible) {
            Button("New game", role: .destructive) { restart() }
            Button("Keep playing") { confirmingNewGame = false }
        } message: { Text("Your best score stays safe, but this round will be replaced.") }
        .onChange(of: viewModel.hasWon) { _, hasWon in if hasWon { showingWin = true } }
        .task { await attachCloud() }
    }

    // Sized to fit an iPhone viewport without scrolling. The previous spacing
    // asked for ~887pt inside an 874pt screen, and that 13pt overflow was the
    // whole bug: it forced the scrolling branch, whose pan recogniser then ate
    // every vertical swipe. Keep the total under the viewport so the static
    // branch is chosen and the board receives its own gestures.
    private var content: some View {
        VStack(spacing: 16) {
            header
            titleBlock
            scoreBar
            board
            actionBar
            // Sync status under the board — guest invite is a floating toast.
            CloudBar(cloud: cloud)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 9) {
                BrandMark().frame(width: 34, height: 34)
                Text("2048").font(.system(size: 18, weight: .heavy, design: .rounded)).tracking(-0.5)
            }
            Spacer(minLength: 4)
            AccountButton(cloud: cloud) {
                if cloud.isSignedIn { showingAccount = true } else { authMode = .login }
            }
            LeaderboardButton { showingLeaderboard = true }
            Button {
                sounds.toggle()
            } label: {
                Image(systemName: sounds.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.black.opacity(0.08)))
            }
            .foregroundStyle(ink)
            .accessibilityLabel(sounds.isEnabled ? "Mute sound" : "Unmute sound")
            .accessibilityIdentifier("soundToggle")
            Button { showingHelp = true } label: { Image(systemName: "questionmark").font(.system(size: 15, weight: .bold)).frame(width: 38, height: 38).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.black.opacity(0.08))) }
            .foregroundStyle(ink).accessibilityLabel("How to play")
        }
    }

    /// The cloud observes the round; the round knows nothing about the cloud.
    @MainActor
    private func attachCloud() async {
        viewModel.onRoundChanged = { [weak cloud, weak viewModel] change in
            guard let cloud, let viewModel else { return }
            Task { @MainActor in
                switch change {
                case .gameOver:
                    await cloud.submitRound(viewModel.cloudSave())
                    await cloud.sync(save: viewModel.cloudSave, apply: { _ = viewModel.applyCloudSave($0) })
                case .restored, .profileChanged:
                    // A round we just downloaded does not need uploading back,
                    // and a profile switch reconciles explicitly straight after.
                    break
                case .move, .undo, .newGame:
                    await cloud.sync(save: viewModel.cloudSave, apply: { _ = viewModel.applyCloudSave($0) })
                }
            }
        }

        // Adopt the right profile before the network is asked. A stored
        // session must never flash the guest board, and a guest move must
        // never reach an account.
        guard cloud.hasStoredSession else { return }
        let adopted = viewModel.beginAccountSession()
        guard await cloud.restore() else {
            viewModel.endAccountSession()
            return
        }
        if adopted == .restored {
            // The cached round is this account's own, so it can be offered.
            await cloud.sync(save: viewModel.cloudSave, apply: { _ = viewModel.applyCloudSave($0) })
        } else {
            await adoptAccountRound()
        }
    }

    /// Hands the device over to a session that has just been granted.
    @MainActor
    private func adoptAccount() async {
        viewModel.beginAccountSession(fresh: true)
        await adoptAccountRound()
    }

    /// Pulls the account's round, then its career best for the Best card.
    @MainActor
    private func adoptAccountRound() async {
        await cloud.adoptAccountRound(apply: { _ = viewModel.applyCloudSave($0) })
        viewModel.adoptCareerBest(cloud.user?.statistics.bestScore ?? 0)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Make space.").font(.system(size: 43, weight: .heavy, design: .rounded)).tracking(-2)
            Text("Find 2048.").font(.system(size: 39, weight: .medium, design: .serif)).italic().foregroundStyle(accent).tracking(-1.5)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private var scoreBar: some View {
        HStack(spacing: 9) {
            ScoreCard(label: "Score", value: viewModel.score, dark: true)
            ScoreCard(label: "Best", value: viewModel.highScore, dark: false)
        }
    }

    private var board: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 8
            let inset: CGFloat = 10
            let tileSize = (proxy.size.width - inset * 2 - gap * 3) / 4
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.663, green: 0.616, blue: 0.557)).shadow(color: Color(red: 0.29, green: 0.24, blue: 0.18).opacity(0.16), radius: 24, y: 14)
                VStack(spacing: gap) {
                    ForEach(0..<viewModel.gridSize, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<viewModel.gridSize, id: \.self) { column in
                                TileView(value: viewModel.grid[row][column]).frame(width: tileSize, height: tileSize)
                            }
                        }
                    }
                }.padding(inset)

                if viewModel.isGameOver() { EndPanel(kicker: "Round complete", title: "No more moves", detail: "Final score: \(viewModel.score.formatted())", primary: "Try again", secondary: nil, primaryAction: restart) }
                else if showingWin { EndPanel(kicker: "Goal reached", title: "You made 2048", detail: "Keep building, or start with a clean board.", primary: "New game", secondary: "Keep playing", primaryAction: restart, secondaryAction: { showingWin = false }) }
            }
            .contentShape(Rectangle())
            // High priority so the board's drag is preferred over gestures in
            // the view hierarchy. This alone does not stop the enclosing
            // ScrollView from panning — a UIScrollView's own recogniser is not
            // a SwiftUI gesture — which is why the ScrollView also pins its
            // bounce to content size.
            .highPriorityGesture(DragGesture(minimumDistance: 22).onEnded(handleDrag))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("GameBoard")
            .accessibilityLabel("2048 game board")
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            ActionButton(title: "Undo", systemImage: "arrow.uturn.backward", disabled: !viewModel.canUndo) {
                viewModel.undo()
                haptic(.soft)
                sounds.undo()
            }
            ActionButton(title: "New game", systemImage: "arrow.clockwise", disabled: false) { confirmingNewGame = viewModel.score > 0; if viewModel.score == 0 { restart() } }
        }
    }

    private func handleDrag(_ gesture: DragGesture.Value) {
        let x = gesture.translation.width
        let y = gesture.translation.height
        let direction: GameViewModel.Direction = abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up)
        let scoreBefore = viewModel.score
        let wonBefore = viewModel.hasWon
        if viewModel.swipe(direction: direction) {
            haptic(.light)
            if viewModel.isGameOver() {
                sounds.gameOver()
            } else if viewModel.hasWon && !wonBefore {
                sounds.win()
            } else if viewModel.score > scoreBefore {
                sounds.merge(points: viewModel.score - scoreBefore)
            } else {
                sounds.move()
            }
        } else {
            haptic(.rigid)
            sounds.invalid()
        }
    }

    private func restart() {
        showingWin = false
        viewModel.restartGame()
        haptic(.medium)
        sounds.newGame()
    }
    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) { UIImpactFeedbackGenerator(style: style).impactOccurred() }
}

private struct BrandMark: View {
    var body: some View { ZStack { RoundedRectangle(cornerRadius: 9).fill(Color(red: 0.141, green: 0.137, blue: 0.122)); VStack(spacing: 3) { HStack(spacing: 3) { square(.white); square(.white) }; HStack(spacing: 3) { square(.white); square(Color(red: 0.914, green: 0.388, blue: 0.271)) } }.padding(8) } }
    private func square(_ color: Color) -> some View { RoundedRectangle(cornerRadius: 1.5).fill(color) }
}

private struct ScoreCard: View {
    let label: String; let value: Int; let dark: Bool
    var body: some View { VStack(alignment: .leading, spacing: 3) { Text(label.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(dark ? Color.white.opacity(0.62) : Color(red: 0.435, green: 0.416, blue: 0.380)); Text(value.formatted()).font(.system(size: 28, weight: .semibold, design: .monospaced)).tracking(-1.5).contentTransition(.numericText()) }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).padding(.vertical, 11).background(dark ? Color(red: 0.141, green: 0.137, blue: 0.122) : Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 13)).overlay { if !dark { RoundedRectangle(cornerRadius: 13).stroke(Color.black.opacity(0.08)) } }.foregroundStyle(dark ? .white : Color(red: 0.141, green: 0.137, blue: 0.122)).accessibilityElement(children: .combine).accessibilityIdentifier("\(label)Card") }
}

private struct TileView: View {
    let value: Int
    var body: some View { Text(value == 0 ? "" : value.formatted()).font(.system(size: fontSize, weight: .bold, design: .monospaced)).tracking(-2).minimumScaleFactor(0.55).foregroundStyle(textColor).frame(maxWidth: .infinity, maxHeight: .infinity).background(tileColor, in: RoundedRectangle(cornerRadius: 11)).contentTransition(.numericText()).animation(.snappy(duration: 0.2), value: value).accessibilityLabel(value == 0 ? "Empty cell" : "Tile \(value)") }
    private var fontSize: CGFloat { value >= 1024 ? 25 : value >= 128 ? 29 : 35 }
    private var textColor: Color { value >= 8 ? .white : Color(red: 0.318, green: 0.294, blue: 0.263) }
    private var tileColor: Color { switch value { case 0: return Color(red: 0.741, green: 0.698, blue: 0.643); case 2: return Color(red: 0.945, green: 0.910, blue: 0.851); case 4: return Color(red: 0.918, green: 0.859, blue: 0.757); case 8: return Color(red: 0.937, green: 0.667, blue: 0.451); case 16: return Color(red: 0.914, green: 0.541, blue: 0.373); case 32: return Color(red: 0.898, green: 0.420, blue: 0.318); case 64: return Color(red: 0.851, green: 0.298, blue: 0.247); case 128: return Color(red: 0.847, green: 0.678, blue: 0.357); case 256: return Color(red: 0.788, green: 0.604, blue: 0.251); case 512: return Color(red: 0.698, green: 0.478, blue: 0.196); case 1024: return Color(red: 0.451, green: 0.357, blue: 0.286); default: return Color(red: 0.141, green: 0.137, blue: 0.122) } }
}

private struct ActionButton: View {
    let title: String; let systemImage: String; let disabled: Bool; let action: () -> Void
    var body: some View { Button(action: action) { Label(title, systemImage: systemImage).font(.system(size: 15, weight: .semibold, design: .rounded)).frame(maxWidth: .infinity).frame(height: 48).background(.white.opacity(disabled ? 0.3 : 0.7), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08))) }.foregroundStyle(Color(red: 0.141, green: 0.137, blue: 0.122)).disabled(disabled).opacity(disabled ? 0.45 : 1) }
}

private struct EndPanel: View {
    let kicker: String; let title: String; let detail: String; let primary: String; let secondary: String?; let primaryAction: () -> Void; var secondaryAction: (() -> Void)? = nil
    var body: some View { VStack(spacing: 9) { Text(kicker.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(Color(red: 0.96, green: 0.65, blue: 0.56)); Text(title).font(.system(size: 31, weight: .heavy, design: .rounded)).tracking(-1.3); Text(detail).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.72)).multilineTextAlignment(.center); HStack { Button(primary, action: primaryAction).buttonStyle(.borderedProminent).tint(Color(red: 0.914, green: 0.388, blue: 0.271)); if let secondary, let secondaryAction { Button(secondary, action: secondaryAction).buttonStyle(.plain) } }.padding(.top, 8) }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.white).background(Color(red: 0.141, green: 0.137, blue: 0.122).opacity(0.94), in: RoundedRectangle(cornerRadius: 18)) }
}

/// The help sheet is the app's one server-drivable surface.
///
/// It renders a published `help` surface when one is available and valid, and
/// the hand-written rows below when it is not. The rules of the game are never
/// described by data — only this content is — so a bad payload costs the player
/// nothing but the default copy.
private struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var resolution: SurfaceResolution?

    var body: some View {
        NavigationStack {
            ScrollView {
                SurfaceView(resolution: resolution) { nativeHelp }
                    .padding(22)
            }
            .background(Color(red: 0.961, green: 0.941, blue: 0.902))
            .navigationTitle("How to play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { resolution = await SurfaceCatalog.shared.resolve(.help) }
        }
    }

    /// The shipped content, and the fallback for every failure mode.
    private var nativeHelp: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Small rules.\nDeep decisions.")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .tracking(-1.8)
            HelpRow(number: "01", title: "Slide", detail: "Swipe the board to move every tile in one direction.")
            HelpRow(number: "02", title: "Match", detail: "Equal tiles merge and add their new value to your score.")
            HelpRow(
                number: "03",
                title: "Protect space",
                detail: "Keep your largest tile in a corner and preserve empty cells."
            )
        }
    }
}

private struct HelpRow: View {
    let number: String; let title: String; let detail: String
    var body: some View { HStack(alignment: .top, spacing: 18) { Text(number).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Color(red: 0.914, green: 0.388, blue: 0.271)); VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).foregroundStyle(.secondary).lineSpacing(4) } }.padding(.vertical, 16).overlay(alignment: .top) { Divider() } }
}

#Preview { GameView() }

// MARK: - Maintainer reference (documentation only)
//
// Product behavior, interface, accessibility, and repository overview.
//
// This section is intentionally comment-only. The named repository files remain
// canonical; their contents are mirrored here as an in-source reading reference.
// No declaration, executable statement, build setting, or runtime behavior follows.

// SOURCE: .github/README.md

// # 2048, Built Three Ways
//
// A polished, accessible, **local-first** 2048 puzzle shipped as **three independent native clients** — a dependency-free progressive web app, a SwiftUI iOS app, and a Jetpack Compose Android app — plus an optional Cloud API for accounts, cross-device save sync, and leaderboards. The clients share no runtime code, yet every one of them is held to the same documented set of behavioral invariants and verified by continuous integration. A move never requires the network.
//
// ![Server-Driven UI](https://img.shields.io/badge/Server--Driven%20UI-5A0FC8?style=for-the-badge&logo=json&logoColor=white)
// ![JavaScript](https://img.shields.io/badge/JavaScript-F7DF1E?style=for-the-badge&logo=javascript&logoColor=black)
// ![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)
// ![Kotlin](https://img.shields.io/badge/Kotlin-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white)
// ![Java](https://img.shields.io/badge/Java%2017-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
// ![HTML5](https://img.shields.io/badge/HTML5-E34F26?style=for-the-badge&logo=html5&logoColor=white)
// ![CSS](https://img.shields.io/badge/CSS-663399?style=for-the-badge&logo=css&logoColor=white)
// ![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
// ![YAML](https://img.shields.io/badge/YAML-CB171E?style=for-the-badge&logo=yaml&logoColor=white)
// ![JSON](https://img.shields.io/badge/JSON-000000?style=for-the-badge&logo=json&logoColor=white)
// ![XML](https://img.shields.io/badge/XML-005FAD?style=for-the-badge&logo=xml&logoColor=white)
// ![Markdown](https://img.shields.io/badge/Markdown-000000?style=for-the-badge&logo=markdown&logoColor=white)
// ![Node.js](https://img.shields.io/badge/Node.js%2022-5FA04E?style=for-the-badge&logo=nodedotjs&logoColor=white)
// ![npm](https://img.shields.io/badge/npm-CB3837?style=for-the-badge&logo=npm&logoColor=white)
// ![PWA](https://img.shields.io/badge/PWA-5A0FC8?style=for-the-badge&logo=pwa&logoColor=white)
// ![SVG](https://img.shields.io/badge/SVG-FFB13B?style=for-the-badge&logo=svg&logoColor=black)
// ![Google Fonts](https://img.shields.io/badge/Google%20Fonts-4285F4?style=for-the-badge&logo=googlefonts&logoColor=white)
// ![Schema.org](https://img.shields.io/badge/Schema.org%20JSON--LD-000000?style=for-the-badge&logo=json&logoColor=white)
// ![Lighthouse](https://img.shields.io/badge/Lighthouse-F44B21?style=for-the-badge&logo=lighthouse&logoColor=white)
// ![Google Chrome](https://img.shields.io/badge/Chromium-4285F4?style=for-the-badge&logo=googlechrome&logoColor=white)
// ![SwiftUI](https://img.shields.io/badge/SwiftUI-0071E3?style=for-the-badge&logo=swift&logoColor=white)
// ![Xcode](https://img.shields.io/badge/Xcode-147EFB?style=for-the-badge&logo=xcode&logoColor=white)
// ![XCTest](https://img.shields.io/badge/XCTest%20%2F%20XCUITest-1B6AC6?style=for-the-badge&logo=swift&logoColor=white)
// ![iOS](https://img.shields.io/badge/iOS%2017.4%2B-000000?style=for-the-badge&logo=ios&logoColor=white)
// ![SF Symbols](https://img.shields.io/badge/SF%20Symbols-000000?style=for-the-badge&logo=apple&logoColor=white)
// ![Android](https://img.shields.io/badge/Android%20SDK%2034-3DDC84?style=for-the-badge&logo=android&logoColor=white)
// ![Jetpack Compose](https://img.shields.io/badge/Jetpack%20Compose-4285F4?style=for-the-badge&logo=jetpackcompose&logoColor=white)
// ![Material Design 3](https://img.shields.io/badge/Material%20Design%203-757575?style=for-the-badge&logo=materialdesign&logoColor=white)
// ![Gradle](https://img.shields.io/badge/Gradle%208.13-02303A?style=for-the-badge&logo=gradle&logoColor=white)
// ![JUnit](https://img.shields.io/badge/JUnit-25A162?style=for-the-badge&logo=junit5&logoColor=white)
// ![Espresso](https://img.shields.io/badge/Espresso-8BC34A?style=for-the-badge&logo=android&logoColor=white)
// ![Android Studio](https://img.shields.io/badge/Android%20Studio-3DDC84?style=for-the-badge&logo=androidstudio&logoColor=white)
// ![Playwright](https://img.shields.io/badge/Playwright-2EAD33?style=for-the-badge&logo=googlechrome&logoColor=white)
// ![c8](https://img.shields.io/badge/c8%20Coverage-4B8BF5?style=for-the-badge&logo=v8&logoColor=white)
// ![Husky](https://img.shields.io/badge/Husky-F05032?style=for-the-badge&logo=git&logoColor=white)
// ![ShellCheck](https://img.shields.io/badge/ShellCheck-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
// ![pre-commit](https://img.shields.io/badge/pre--commit-FAB040?style=for-the-badge&logo=precommit&logoColor=black)
// ![EditorConfig](https://img.shields.io/badge/EditorConfig-E0EFEF?style=for-the-badge&logo=editorconfig&logoColor=black)
// ![GNU Make](https://img.shields.io/badge/GNU%20Make-6D00CC?style=for-the-badge&logo=make&logoColor=white)
// ![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
// ![Dev Containers](https://img.shields.io/badge/Dev%20Containers-007ACC?style=for-the-badge&logo=docker&logoColor=white)
// ![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-2088FF?style=for-the-badge&logo=githubactions&logoColor=white)
// ![GitHub Pages](https://img.shields.io/badge/GitHub%20Pages-222222?style=for-the-badge&logo=githubpages&logoColor=white)
// ![Git](https://img.shields.io/badge/Git-F05032?style=for-the-badge&logo=git&logoColor=white)
// ![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)
//
// **[▶ Play the web version](https://hoangsonww.github.io/2048-Game/)** · [Download the apps](https://github.com/hoangsonww/2048-Game/releases/latest) · [Cloud API docs](https://game-2048-cloud-api.vercel.app/docs) · [Rules and strategy](https://hoangsonww.github.io/2048-Game/Web-Version/about.html) · [Report an issue](https://github.com/hoangsonww/2048-Game/issues) · [Contributing](CONTRIBUTING.md) · [Security policy](SECURITY.md)
//
// ---
//
// ## Table of contents
//
// - [Why this project exists](#why-this-project-exists)
// - [Screenshots](#screenshots)
// - [Feature matrix](#feature-matrix)
// - [How to play](#how-to-play)
// - [Controls](#controls)
// - [Behavioral invariants](#behavioral-invariants)
// - [Architecture](#architecture)
// - [Cloud API](#cloud-api)
// - [Server-driven surfaces](#server-driven-surfaces)
// - [Repository map](#repository-map)
// - [Getting started](#getting-started)
// - [Run the web app](#run-the-web-app)
// - [Run the iOS app](#run-the-ios-app)
// - [Run the Android app](#run-the-android-app)
// - [Command reference](#command-reference)
// - [Testing and quality gates](#testing-and-quality-gates)
// - [Continuous integration](#continuous-integration)
// - [Releases and downloads](#releases-and-downloads)
// - [Accessibility](#accessibility)
// - [Privacy and data handling](#privacy-and-data-handling)
// - [Web discoverability and PWA install](#web-discoverability-and-pwa-install)
// - [Agent-ready development](#agent-ready-development)
// - [Troubleshooting](#troubleshooting)
// - [Contributing](#contributing)
// - [Security](#security)
// - [Citation](#citation)
// - [License and credits](#license-and-credits)
//
// ---
//
// ## Why this project exists
//
// 2048 is a small enough game that its rules fit in a paragraph, which makes it an unusually good vehicle for a harder question: **how do you keep three separately written native clients behaving identically, without a shared runtime, a cross-platform framework, or a code generator?**
//
// This repository is the worked answer. There is no React Native layer, no Kotlin Multiplatform module, no WebView wrapper. Each client is idiomatic for its platform — vanilla ES modules on the web, SwiftUI with `@Observable`-style view models on iOS, Compose with a `ViewModel` on Android — and parity is maintained by three deliberate mechanisms instead:
//
// 1. **A written invariant contract.** [`ARCHITECTURE.md`](../ARCHITECTURE.md), [`AGENTS.md`](../AGENTS.md), and [`docs/architecture.md`](../docs/architecture.md) define the exact rules every client must satisfy, down to edge cases like "an ineffective move must not spawn a tile."
// 2. **Per-client deterministic rules tests.** Each platform independently proves the same behavior list against its own engine, with randomness injected so results are reproducible.
// 3. **A CI pipeline that runs all three toolchains on every pull request.** A parity regression in any one client fails the build.
//
// The result is a codebase where you can read one platform's implementation in isolation and still trust it matches the others.
//
// ---
//
// ## Screenshots
//
// The same experience on all three clients. `make screenshots-web` captures the browser states; `make screenshots-mobile` drives a booted iPhone simulator and Android emulator. Both commands promote the reviewed canonical set into `images/`.
//
// | Web | iOS | Android |
// | :---: | :---: | :---: |
// | ![2048 web app with guest invite, Sign in, leaderboard control, and 4×4 board](../images/web-version-UI.png) | ![2048 SwiftUI app on iPhone with Sign in, leaderboard, help, and guest sync banner](../images/IOS-UI.png) | ![2048 Jetpack Compose app on Pixel with Sign in, leaderboard, and guest account banner](../images/android-ui.png) |
//
// ### Web states
//
// | Mobile layout | Win | Game over |
// | :---: | :---: | :---: |
// | ![The web game at a 390px mobile width with on-screen direction controls](../images/web-mobile-gameplay.png) | ![The win overlay after reaching 2048, offering a new game or continued play](../images/web-win.png) | ![The game-over overlay on a full board with no available merges](../images/web-loss.png) |
//
// | New-game confirmation | Rules and strategy |
// | :---: | :---: |
// | ![The restart confirmation dialog warning that the current round will be replaced](../images/web-restart-dialog.png) | ![The About page describing the rules, strategy, and project details](../images/web-about.png) |
//
// ### Optional cloud surfaces
//
// Guest play, auth, sync, and leaderboards — local-first; an account is never required.
//
// | Guest invite (desktop) | Create account | Sign in |
// | :---: | :---: | :---: |
// | ![Guest banner inviting account creation above the board](../images/web-cloud-guest.png) | ![Create-account dialog with username, email, and password](../images/web-cloud-signup.png) | ![Sign-in dialog with username-or-email and password](../images/web-cloud-signin.png) |
//
// | Handover warning | Reset password | |
// | :---: | :---: | :---: |
// | ![Dialog warning that signing in sets the current round aside](../images/web-cloud-handover.png) | ![Reset dialog asking for username, email, and a new password twice](../images/web-cloud-reset.png) | |
//
// | Signed in | Leaderboard | Account panel |
// | :---: | :---: | :---: |
// | ![Signed-in header and cloud sync status under the board](../images/web-cloud-signed-in.png) | ![Leaderboard dialog with Today / This week / All time periods](../images/web-cloud-leaderboard.png) | ![Account panel with profile summary, sync time, and sign out](../images/web-cloud-account.png) |
//
// | Mobile guest | Mobile create account | Android create account |
// | :---: | :---: | :---: |
// | ![Mobile layout with guest invite and on-screen controls](../images/web-cloud-mobile-guest.png) | ![Mobile create-account dialog](../images/web-cloud-mobile-signup.png) | ![Android Compose create-account bottom sheet](../images/android-cloud-signup.png) |
//
// | Android guest | Android leaderboard | Android sign in |
// | :---: | :---: | :---: |
// | ![Android guest banner above the board](../images/android-cloud-guest.png) | ![Android leaderboard bottom sheet](../images/android-cloud-leaderboard.png) | ![Android sign-in bottom sheet](../images/android-cloud-signin.png) |
//
// | iOS create account | iOS handover warning | iOS password reset |
// | :---: | :---: | :---: |
// | ![iOS create-account sheet with password confirmation](../images/ios-cloud-signup.png) | ![iOS warning that the guest round will be set aside](../images/ios-cloud-handover.png) | ![iOS password-reset sheet](../images/ios-cloud-reset.png) |
//
// | Android handover warning | Android password reset | iOS leaderboard |
// | :---: | :---: | :---: |
// | ![Android warning that the guest round will be set aside](../images/android-cloud-handover.png) | ![Android password-reset bottom sheet](../images/android-cloud-reset.png) | ![iOS leaderboard sheet](../images/ios-cloud-leaderboard.png) |
//
// QA-only output without promotion: `make screenshots-web-qa` writes `output/playwright/latest/`; `make screenshots-mobile-qa` writes `output/mobile/`.
//
// ---
//
// ## Feature matrix
//
// | Capability | Web | iOS | Android |
// | --- | :---: | :---: | :---: |
// | Correct compaction, single-merge, and scoring rules | ✅ | ✅ | ✅ |
// | No tile spawn after an ineffective move | ✅ | ✅ | ✅ |
// | 90 % `2` / 10 % `4` weighted tile spawning | ✅ | ✅ | ✅ |
// | One-step undo (board **and** score) | ✅ | ✅ | ✅ |
// | Persistent best score across sessions | ✅ | ✅ | ✅ |
// | Automatic session restore on launch | ✅ | ✅ | ✅ |
// | Corrupt-save detection and safe discard | ✅ | ✅ | ✅ |
// | Restart confirmation while a round is active | ✅ | ✅ | ✅ |
// | Win state at 2048 with "keep playing" option | ✅ | ✅ | ✅ |
// | Game-over detection on a full board with no merge | ✅ | ✅ | ✅ |
// | In-app rules and strategy guide | ✅ | ✅ | ✅ |
// | Server-driven content surfaces, with a native fallback | — | ✅ | ✅ |
// | Swipe / drag gesture input | ✅ | ✅ | ✅ |
// | Physical keyboard input (arrows + WASD) | ✅ | — | — |
// | On-screen direction controls | ✅ | — | — |
// | Fullscreen toggle | ✅ | — | — |
// | Haptic feedback | — | ✅ | ✅ |
// | Procedural sound cues with a mute toggle | ✅ | ✅ | ✅ |
// | Separate guest and signed-in rounds on one device | ✅ | ✅ | ✅ |
// | Reduced-motion support | ✅ | ✅ | ✅ |
// | Screen-reader announcements | ✅ | ✅ | ✅ |
// | Vector-only iconography | SVG | SF Symbols | Material vectors |
// | Installable / distributable | PWA | `.app` | `.apk` |
// | Works fully offline | ✅ | ✅ | ✅ |
// | Optional account, cloud save sync, leaderboards | ✅ | ✅ | ✅ |
// | Password confirmation, per-field reveal, and reset | ✅ | ✅ | ✅ |
// | Mandatory network for a move | ❌ | ❌ | ❌ |
//
// ---
//
// ## How to play
//
// Every move slides **all** tiles as far as they can go in one direction. When two tiles bearing the same number collide, they merge into a single tile of twice the value, and that new value is added to your score. After any move that actually changed the board, one new tile appears in a random empty cell — a `2` ninety percent of the time, a `4` the other ten.
//
// The round ends when the board is full **and** no two adjacent tiles match, because at that point no move can change anything. Reaching a `2048` tile triggers the win state, but you are free to dismiss it and keep building toward 4096 and beyond.
//
// Three practical habits carry most beginners a long way:
//
// - **Anchor a corner.** Pick one corner, keep your largest tile there, and avoid any move that would dislodge it.
// - **Keep one row or column as a "spine."** Build a descending run along the edge that holds your anchor so merges cascade naturally.
// - **Treat the fourth direction as a last resort.** If you anchor bottom-left, moving up is what breaks the structure — spend it only when you have no alternative.
//
// ---
//
// ## Controls
//
// | Action | Web | iOS | Android |
// | --- | --- | --- | --- |
// | Move | Arrow keys, `W`/`A`/`S`/`D`, swipe on the board, or the on-screen direction pad | Swipe the board in any direction | Swipe the board in any direction |
// | Undo last move | Undo button | Undo button | Undo button |
// | New game | New game button (confirms first if a round is in progress) | New game button (confirms first) | New game button (confirms first) |
// | Sign in / account | Header account button | Account control | Account control |
// | Leaderboard | Leaderboard button | Leaderboard | Leaderboard |
// | Rules and help | About link | Help button | Help button |
// | Fullscreen | `F` | — | — |
// | Continue past 2048 | "Keep playing" in the win overlay | "Keep playing" | "Keep playing" |
//
// A swipe registers once the gesture travels past a small threshold, so a single drag always produces exactly one move — never a burst.
//
// ---
//
// ## Behavioral invariants
//
// These are the contract. Every client must satisfy all of them, and each one is covered by at least one automated test per platform.
//
// 1. A valid move compacts tiles toward the travel direction, merges each pair of equal neighbors **at most once per move**, adds the merged values to the score, and then spawns exactly one new tile.
// 2. An ineffective move — one where no tile can slide or merge — changes nothing: no score change, no new tile, and **no undo snapshot**.
// 3. Undo restores exactly the board and score as they were immediately before the most recent valid move. The snapshot is consumed on use, so undo is strictly one step.
// 4. Starting a new game preserves the best score and requires explicit confirmation whenever a round is already in progress.
// 5. Reaching 2048 presents a win state that the player may dismiss to continue playing. A full board with no available merge presents game over.
// 6. Persisted state is validated on load. Anything structurally invalid — wrong board length, non-power-of-two values, negative scores, malformed JSON — is discarded and replaced with a fresh game rather than crashing or restoring a corrupt board.
// 7. Randomness is injectable in every client so tests are fully deterministic, while production always uses unbiased platform randomness.
// 8. The guest round and the signed-in round are separate. Signing in warns before taking a round off the screen, parks it untouched, and loads the account's own; signing out restores it exactly, best score included. Career statistics come from the account and are never lifted from local storage.
// 9. A sound cue is heard now or dropped. No client queues a cue it cannot play immediately — a backlog arriving seconds after the moves that caused it is worse than silence.
//
// ---
//
// ## Architecture
//
// Three clients, three runtimes, one contract. There is no shared rules library. Play is local-first: a move never requires the network. An optional Cloud API (`server/`) adds accounts, cross-device sync, and leaderboards — see [docs/backend.md](../docs/backend.md).
//
// | Concern | Web | iOS | Android |
// | --- | --- | --- | --- |
// | UI layer | `index.html`, `Web-Version/style.css` | `GameView.swift`, `ContentView.swift` | `MainActivity.kt` + Compose theme |
// | Rules engine | `Web-Version/game-engine.js` (pure, side-effect free) | `GameViewModel.swift` | `GameViewModel.kt` |
// | State orchestration | `Web-Version/script.js` | `GameViewModel.swift` | `GameViewModel.kt` |
// | Persistence | `localStorage`, key `game2048-state-v2` | `UserDefaults` | `GameStorage.kt` over `SharedPreferences` |
// | Server-driven content | — | `Game-2048/SDUI/` | `sdui/` package |
// | Unit tests | Node.js built-in test runner | XCTest | JUnit 4 |
// | UI / integration tests | Playwright (Chromium) | XCUITest | Compose UI Test + Espresso |
// | Language | JavaScript (ES modules) | Swift 5 | Kotlin 1.9 |
//
// **The move algorithm**, identical in all three: for each row or column taken in travel order, drop the empty cells, walk the remaining values merging adjacent equal pairs exactly once, pad the line back to length four with zeros, and write it back. Compare the resulting board to the original — spawn a tile only if they differ.
//
// **The lifecycle**, identical in all three:
//
// 1. Load persisted state and validate it, or build a fresh board with two starting tiles.
// 2. Accept a direction from keyboard, button, or gesture input.
// 3. Resolve the move atomically, capturing an undo snapshot first if the move is valid.
// 4. Persist board, score, best score, and win-continuation flag.
// 5. Evaluate the win and game-over predicates and present the matching UI.
//
// **Web delivery** is static files served from `/2048-Game/` on GitHub Pages. Canonical URLs, manifest scope, sitemap entries, and crawler discovery links must all keep that base path. The local development server deliberately disables caching so UI edits reload predictably.
//
// Deeper detail lives in [`ARCHITECTURE.md`](../ARCHITECTURE.md) for the whole system, and [`docs/architecture.md`](../docs/architecture.md) for per-client specifics.
//
// ---
//
// ## Cloud API
//
// Optional Express + MongoDB Atlas service for accounts, JWT auth, cross-device save sync, scores, and leaderboards. Live at [game-2048-cloud-api.vercel.app](https://game-2048-cloud-api.vercel.app) — the service root (`/`) redirects to Swagger UI at `/docs`.
//
// | Surface | URL |
// | --- | --- |
// | Swagger UI | [/docs](https://game-2048-cloud-api.vercel.app/docs) |
// | Redoc | [/redoc](https://game-2048-cloud-api.vercel.app/redoc) |
// | Scalar | [/reference](https://game-2048-cloud-api.vercel.app/reference) |
// | OpenAPI JSON | [/openapi.json](https://game-2048-cloud-api.vercel.app/openapi.json) |
//
// Play stays local-first: declining an account leaves the board unchanged. Full contract, sync rules, and local run notes: [`docs/backend.md`](../docs/backend.md). Privacy: [`docs/privacy.md`](../docs/privacy.md).
//
// ---
//
// ## Server-driven surfaces
//
// Both native clients ship a **server-driven UI runtime that does not fetch over the network today.**
//
// Store review takes days. A typo in the help copy should not have to wait that long, and every mature store app solves this by describing the screen with data rather than code it ships. Help surfaces are described by JSON, validated, and rendered natively from the app bundle — the same contract that could later load from a publisher without rewriting the renderer. The optional Cloud API handles accounts and sync; it does not drive help copy today. Adding a remote surface source later is one new `SurfaceSource` and one line of wiring; the renderer, validator, and every test stay untouched.
//
// **The game is never server-driven.** Board, merging, scoring, and undo are code, and no payload can reach them. What is describable is content — the help sheet today.
//
// | A payload may | A payload may not |
// | --- | --- |
// | Supply text, ordering, and structure | Supply colours, fonts, or spacing |
// | Name an action the host already implements | Describe behaviour, expressions, or scripts |
// | Introduce a node type this build skips | Touch the rules engine or persisted state |
// | Gate itself to a minimum app version | Force a screen to render nothing |
//
// Actions are **names**. A surface can ask for `newGame`; it cannot describe how to start one. That indirection is what keeps a data channel from becoming an execution channel.
//
// Every surface has a hand-written native fallback. Missing, unreadable, schema too new, app too old, or every node unknown all end at the shipped UI, and individual bad nodes are pruned while their siblings render. Delete every payload and both apps are exactly what they shipped with — the feature is additive, never load-bearing.
//
// The iOS and Android payloads are byte-identical and a test asserts they stay that way, for the same reason the rules have three parallel suites: two clients drifting apart is the failure mode this repository exists to prevent.
//
// Full detail in [`ARCHITECTURE.md`](../ARCHITECTURE.md#server-driven-surfaces).
//
// ## Repository map
//
// ```text
// .
// ├── index.html                          Web entry point, SEO metadata, JSON-LD
// ├── 404.html                            GitHub Pages fallback page
// ├── manifest.json                       PWA manifest (icons, shortcuts, scope)
// ├── robots.txt / sitemap.xml            Crawler directives and canonical URL set
// ├── llms.txt / llms-full.txt            Machine-readable product documentation
// ├── humans.txt                          Credits
// ├── Makefile                            Stable developer command surface
// ├── CITATION.cff                        Citation metadata
// │
// ├── Web-Version/
// │   ├── game-engine.js                  Pure deterministic rules engine
// │   ├── script.js                       State, input handling, persistence, DOM
// │   ├── cloud.js / account.js           Optional Cloud API client and account UI
// │   ├── style.css                       Shared visual system and responsive layout
// │   └── about.html                      Rules and strategy guide
// │
// ├── Game-2048/                          SwiftUI client
// │   ├── Game_2048App.swift              App entry point
// │   ├── GameView.swift                  Responsive native board and controls
// │   ├── GameViewModel.swift             Rules, scoring, undo, persistence
// │   ├── Cloud/                          Optional account, sync, leaderboard
// │   └── Assets.xcassets                 App icons and colors
// ├── Game-2048Tests/                     XCTest model and cloud tests
// ├── Game-2048UITests/                   XCUITest interaction and launch tests
// ├── 2048 Game.xcodeproj                 Xcode project (scheme: Game-2048)
// │
// ├── Android-Version/Game2048/           Jetpack Compose client
// │   ├── app/src/main/java/…             MainActivity, GameViewModel, cloud/, GameStorage, theme
// │   ├── app/src/test/java/…             JUnit ViewModel and cloud tests
// │   ├── app/src/androidTest/java/…      Compose instrumentation tests
// │   └── gradle/libs.versions.toml       Version catalog
// │
// ├── server/                             Optional Cloud API (Express + MongoDB Atlas)
// │
// ├── tests/
// │   ├── web/                            Engine, static-metadata, and browser tests
// │   └── tooling/                        Repository-structure tests
// ├── scripts/                            Bootstrap, doctor, checks, per-platform test runners
// ├── docs/                               Architecture, testing, and agent-harness guides
// ├── images/                             App icons, brand mark, share art, screenshots
// │
// ├── .github/
// │   ├── workflows/                      CI, dependency review, labeler
// │   ├── ISSUE_TEMPLATE/                 Bug and feature forms
// │   └── README.md · CONTRIBUTING.md · SECURITY.md · SUPPORT.md · CODE_OF_CONDUCT.md
// ├── .agents/skills/                     Canonical coding-agent workflows
// ├── .claude/skills/                     Claude Code adapters
// └── .devcontainer/                      Node 22, JDK 17, Android SDK 34 container
// ```
//
// `output/` is generated locally by the QA and screenshot scripts and is intentionally not versioned — it is fully reproducible with `make test`, `make screenshots-web`, and `make screenshots-mobile` on a host with both native runtimes.
//
// ---
//
// ## Getting started
//
// | Target | Requirements | Supported hosts |
// | --- | --- | --- |
// | Web | Node.js 22+, npm | macOS, Linux, Windows, dev container |
// | Web browser tests | The above, plus Chromium via `npx playwright install chromium` | macOS, Linux, dev container |
// | iOS | Xcode 15.3+, iOS 17.4+ simulator or device | macOS only |
// | Android | Android SDK 34, API 24+ emulator or device. **No JDK setup needed** — Gradle downloads its own JDK 17. | macOS, Linux, Windows, dev container |
//
// **You do not need to configure a JDK for Android.** Gradle 8.13 daemon JVM criteria are committed in `Android-Version/Game2048/gradle/gradle-daemon-jvm.properties`, so the first `./gradlew` invocation downloads a matching Adoptium JDK 17 for your OS and architecture and runs on it — even if your machine's default `java` is a different version, and even if you have no JDK at all. This is the single most common Android onboarding failure, and it is designed out rather than documented around.
//
// Clone and bootstrap:
//
// ```bash
// git clone https://github.com/hoangsonww/2048-Game.git
// cd 2048-Game
// make setup     # installs locked npm dependencies and activates Git hooks
// make doctor    # reports which platform toolchains this machine can build
// make help      # lists every supported workflow
// ```
//
// `make doctor` is the fastest way to find out what you can run locally. It reports the status of Git, Node, npm, the JDK, ShellCheck, Docker, `xcodebuild`, `xcrun`, `ANDROID_HOME`, and `adb`, so you know up front whether the iOS or Android suites are available before you try them.
//
// To include the Chromium download that the browser tests need, run setup as:
//
// ```bash
// ./scripts/bootstrap.sh --with-browser
// ```
//
// Plain `make setup` skips it to keep first-run setup light, and prints the one-line command to add it later.
//
// Then run any client with a single command:
//
// ```bash
// make serve         # web app at http://localhost:8080
// make android-run   # build, install, and launch on a device or emulator
// make ios-run       # build, install, and launch on a simulator
// ```
//
// **Dev container.** `.devcontainer/` provisions Node.js 22, JDK 17, Android SDK 34 with build-tools 34.0.0, ShellCheck, GNU Make, the GitHub CLI, and Chromium for Playwright, on top of the Microsoft Java 17 Bookworm base image. Open the repository in VS Code and choose **Reopen in Container**, or use GitHub Codespaces.
//
// It covers the complete web and Android JVM workflows out of the box. **iOS cannot be containerized** — Xcode is macOS-only and its license forbids redistribution, so iOS builds always require a macOS host. That is a platform constraint, not a gap in this setup.
//
// To verify the container yourself:
//
// ```bash
// make verify-devcontainer               # build the image and check every tool
// ./scripts/verify-devcontainer.sh --build   # additionally build the Android client inside it
// ```
//
// The `--build` form uses an isolated `git archive` copy rather than mounting your working tree, so a container build never contends with a host build over the same Gradle output directory.
//
// **Git hooks.** Husky activates during `npm install`: `pre-commit` runs the fast repository checks and `pre-push` runs the full web suite. Contributors who prefer the Python framework can install the equivalent hooks from `.pre-commit-config.yaml` with `pre-commit install --install-hooks`.
//
// ---
//
// ## Run the web app
//
// ```bash
// npm install
// npm start          # or: make serve
// ```
//
// Open `http://localhost:8080`. The app is entirely static — no bundler, no transpiler, no production build step, and no third-party runtime dependencies. The only external resource it touches is the Google Fonts stylesheet for the display typeface, and the layout degrades gracefully to system fonts if that request is blocked.
//
// Run the full web suite:
//
// ```bash
// npx playwright install chromium    # one-time browser download
// npm test                           # or: make test-web
// ```
//
// Capture deterministic UI screenshots across desktop and mobile viewports:
//
// ```bash
// make screenshots-web
// ```
//
// Output lands in `output/playwright/` (gitignored) covering gameplay, the restart dialog, win, loss, and the About page at both breakpoints.
//
// With an iPhone simulator and Android emulator already booted, refresh the native canonical set with `make screenshots-mobile`. The script installs the current Android APK, captures both clients through accessibility-labelled controls, and exports the iOS frames from XCTest attachments.
//
// ---
//
// ## Run the iOS app
//
// Requirements: Xcode 15.3 or newer, targeting iOS 17.4+. The app builds for both iPhone and iPad.
//
// The fastest path needs no Xcode UI and no device UDID — one command builds, installs, and launches on an automatically selected simulator:
//
// ```bash
// make ios-run
// ```
//
// Other entry points:
//
// ```bash
// make ios-devices   # list available iPhone simulators
// make ios-boot      # boot a simulator and open Simulator.app
// make ios-build     # build only
// make test-ios      # full model + UI test run with coverage
// ```
//
// Every one of these resolves a simulator for you. To pin a specific device, set `IOS_SIMULATOR_ID` to a UDID from `make ios-devices`.
//
// To work in Xcode instead:
//
// 1. Open `2048 Game.xcodeproj`.
// 2. Select the **Game-2048** scheme and any iPhone or iPad simulator.
// 3. Run with `⌘R`. Run the unit and UI tests with `⌘U`.
//
// ---
//
// ## Run the Android app
//
// Requirements: Android SDK 34 and an API 24 or newer emulator or device. `minSdk` is 24; `compileSdk` and `targetSdk` are 34. **A JDK is not a prerequisite** — Gradle provisions its own.
//
// Build, install, and launch on a connected device or emulator in one command:
//
// ```bash
// make android-run
// ```
//
// Other entry points, all from the repository root:
//
// ```bash
// make android-build          # debug APK
// make android-install        # build and install
// make android-tasks          # list every available Gradle task
// make android-clean          # remove build output
// make test-android           # unit tests, lint, and APK assembly
// make test-android-device    # adds the Compose suite on a connected device
// make gradle ARGS="assembleRelease"   # any other Gradle task
// ```
//
// Every one of these routes through `scripts/android.sh`, which guarantees a correct JDK before invoking Gradle.
//
// Raw Gradle also works, thanks to the committed daemon JVM criteria:
//
// ```bash
// cd Android-Version/Game2048
// ./gradlew assembleDebug
// ```
//
// The first run downloads a matching JDK 17 (roughly 180 MB, cached in `~/.gradle/jdks/`) and every run after that is fast.
//
// To work in Android Studio instead, open `Android-Version/Game2048`, let the Gradle sync finish, then run the `app` configuration.
//
// The debug APK is written to `Android-Version/Game2048/app/build/outputs/apk/debug/app-debug.apk`. If you only want to *play* the Android app, download the prebuilt APK from the [latest release](https://github.com/hoangsonww/2048-Game/releases/latest) instead — no toolchain required.
//
// ---
//
// ## Command reference
//
// Every workflow has a stable `make` entry point. Prefer these over ad-hoc commands — they are what CI and the Git hooks call.
//
// | Command | What it does | Requires |
// | --- | --- | --- |
// | `make help` | Lists all supported workflows | — |
// | `make setup` | Installs locked dependencies and activates Git hooks | Node 22+ |
// | `make doctor` | Reports which platform toolchains are available | — |
// | `make serve` | Serves the web app at `http://localhost:8080` | Node 22+ |
// | `make check` | Fast syntax, repository, shell, SEO, and discovery checks | Node 22+ |
// | `make version` | Prints the version and checks every client agrees | — |
// | `make version-sync` | Rewrites the derived version fields from `VERSION` | — |
// | `make test-web` | Complete deterministic and browser web suite | Node 22+, Chromium |
// | `make android-build` | Builds the Android debug APK | SDK 34 |
// | `make android-install` | Builds and installs on a connected device | SDK 34 + device |
// | `make android-run` | Installs and launches on a connected device | SDK 34 + device |
// | `make android-tasks` | Lists every available Gradle task | SDK 34 |
// | `make android-clean` | Removes Android build output | SDK 34 |
// | `make gradle ARGS="…"` | Runs any Gradle task with a correct JDK | SDK 34 |
// | `make test-android` | Android unit tests, lint, and debug APK | SDK 34 |
// | `make test-android-device` | Adds Compose tests on a connected device | Above + emulator/device |
// | `make ios-build` | Builds the iOS app for a simulator | macOS, Xcode |
// | `make ios-run` | Builds, installs, and launches on a simulator | macOS, Xcode |
// | `make ios-boot` | Boots a simulator and opens Simulator.app | macOS, Xcode |
// | `make ios-devices` | Lists available iPhone simulators | macOS, Xcode |
// | `make test-ios` | iOS unit and UI tests on an available simulator | macOS, Xcode |
// | `make test` | Every suite this host can support | Varies |
// | `make screenshots-web` | Deterministic desktop/mobile + cloud UI captures; promotes into `images/` | Node 22+, Chromium |
// | `make screenshots-web-qa` | Same captures into `output/` only (no promote) | Node 22+, Chromium |
// | `make screenshots-mobile` | iOS/Android game + cloud UI captures; promotes into `images/` | macOS, Xcode, SDK 34, booted simulator + emulator |
// | `make screenshots-mobile-qa` | Same native captures into `output/mobile/` only | Same as above |
// | `make clean-web` | Removes generated coverage and local screenshots | — |
//
// ---
//
// ## Testing and quality gates
//
// Coverage is layered deliberately: pure rules logic is tested exhaustively and cheaply, while the expensive browser, simulator, and emulator suites focus on real user flows that unit tests cannot reach.
//
// ### Web — 253 tests, 100 % line coverage
//
// - **23 deterministic engine tests** against `game-engine.js`, covering all four directions, merge ordering and the single-merge rule, scoring, weighted spawning at its exact boundary, ineffective moves, undo semantics, win and loss predicates, and rejection of structurally invalid boards.
// - **45 controller tests** against `script.js`, run on a hand-written DOM so keyboard, touch, on-screen buttons, rendering, message states, and persistence are all covered without a browser. Includes the gesture-ownership contract: the `touchmove` listener must be non-passive, must suppress scrolling only during a board swipe, and must forget a cancelled gesture.
// - **34 cloud-bridge tests** for the guest and account storage profiles: that signing in parks the guest round rather than uploading it, that signed-in play never writes to the guest slot, and that signing out restores the guest round exactly.
// - **47 cloud-client tests** for auth, token refresh, sync resolutions, password reset, and the rule that career statistics are never lifted from local storage, plus **72 account-surface tests** for the dialogs, the handover warning, password confirmation, and the reveal controls.
// - **13 sound tests** proving a cue is dropped rather than queued whenever it cannot be played now.
// - **5 metadata and asset tests** for the manifest, sitemap, `robots.txt`, JSON-LD, form patterns, and every referenced icon, plus **2 repository-tooling tests** asserting the project structure and npm script surface stay intact.
// - **13 Chromium interaction scenarios** driving the real page: arrow-key play, WASD play, touch swipe, the on-screen direction pad, undo, persistence across reload, restart confirmation, fullscreen, the win overlay, the loss overlay, recovery from a corrupt saved state, board-swipe ownership, real-clock sound timing, account and password flows, and responsive layout from a 320 px phone through tablet widths.
//
// Coverage is **enforced** by `c8` across everything in `Web-Version/`, and the build fails below 100 % statements, 100 % lines, 100 % functions, or 95 % branches. It currently reaches **100 % statements, lines, and functions with 95.1 % branches**.
//
// ### iOS — 183 tests, 95.1 % domain line coverage
//
// - **80 deterministic model, surface, and render tests** covering every direction, merge ordering, scoring, spawn distribution and index clamping, restart, undo depth and win-state rewind, persistence round-trips, best-score retention, win and loss detection, and rejection of every shape of invalid saved state.
// - **16 profile and sound tests** covering guest / account separation, the career-best seed, and the cue renderer's envelope and pitch slide.
// - **74 cloud tests** across the API client, the controller state machine, the token store, and the wire models — including password reset, every unexpected-failure path, and the rule that career statistics come from the account alone.
// - **12 XCUITest simulator tests** covering the help sheet, swipe gestures, the restart confirmation dialog, accessibility identifiers and labels, end-state recovery flows, launch performance, the account and reset sheets, the password confirmation and reveal controls, the sign-in handover warning, and that a vertical board swipe reaches the board without moving the screen. The suite reports thirteen executions because the launch test runs once per appearance mode.
//
// Coverage is **enforced**: `scripts/test-ios.sh` reads the `.xcresult` with `xccov` and fails below 90 % line coverage of stable app/domain code, currently **95.1 %**. `GameView.swift` and `CloudViews.swift` are exercised by the simulator suite instead: Xcode versions expose different generated executable-line counts for SwiftUI view builders, so including them would make the same source pass or fail according to the installed compiler.
//
// ### Android — 213 tests, 97.2 % domain line coverage
//
// - **49 deterministic ViewModel tests** proving the same rules and persistence contract as the other two clients, including the guest / account profile separation and the career-best seed.
// - **33 server-driven surface tests** covering decoding, version gating, node pruning, source fallback, and the rule that every failure mode ends at the app's own native UI.
// - **11 storage tests** covering `SharedPreferencesGameStorage` serialisation against an in-memory `SharedPreferences`, including truncated, non-numeric, and empty saved grids, and that the guest and account slots cannot see each other.
// - **80 cloud tests** across the API client, the controller state machine, and the token store — including password reset and the rule that career statistics come from the account alone.
// - **6 sound tests** proving a flood of cues is capped rather than buffered, and that an unavailable audio device costs the game nothing.
// - **20 Compose instrumentation tests** on an API 34 emulator covering the help sheet, swipe and undo, restart confirmation, win/loss recovery, the guest invite, the account surface, the sign-in destination, the sign-in handover warning, and the password confirmation, reveal, and reset flows.
//
// Coverage is **enforced** by JaCoCo: `make test-android` fails below 90 % line or 85 % branch coverage of the Kotlin rules engine and storage, currently **97.2 % lines and 85.7 % branches**. `MainActivity` and `CloudUi` are Compose and are measured by the device suite instead.
//
// ### Static and repository checks
//
// `make check` runs on every commit through Husky and validates JavaScript syntax, JSON well-formedness, repository structure, required SEO and discovery files, `llms.txt` availability, staged-file whitespace, and — when ShellCheck is installed — every shell script in `scripts/` and `.husky/`.
//
// ```bash
// make check        # fast pre-commit checks
// make test-web     # full web suite
// make test-ios     # macOS + Xcode
// make test-android # JDK 17 + SDK 34
// make test         # everything this host supports
// ```
//
// More detail, including how to diagnose flaky device runs, is in [`docs/testing.md`](../docs/testing.md).
//
// ---
//
// ## Continuous integration
//
// [Cross-platform CI](workflows/ci.yml) runs on every push to `main`, every pull request, and on manual dispatch. It is split into six independently visible jobs so a failure points straight at the responsible platform:
//
// | Job | Runner | Covers |
// | --- | --- | --- |
// | **Web** | `ubuntu-latest` | `npm audit`, syntax, repository and SEO validation, ShellCheck, enforced engine coverage, Chromium flows |
// | **iOS** | `macos-15` | `build-for-testing`, XCTest model coverage, XCUITest interaction and accessibility flows |
// | **Android JVM** | `ubuntu-latest` | ViewModel unit tests, Android lint, debug APK assembly |
// | **Android device** | `ubuntu-latest` + KVM | API 34 `pixel_6` emulator running the full Compose instrumentation suite |
// | **Docker** | `ubuntu-latest` | `linux/amd64` and `linux/arm64` image build, a smoke test that actually serves the game, and publication to GHCR |
// | **Android builder** | `ubuntu-latest` | `linux/amd64` SDK image, a containerized APK build with unit tests, and publication to GHCR |
//
// Web coverage reports, Xcode `.xcresult` bundles, Android lint and test reports, and the debug APK are uploaded as workflow artifacts — including on failure, which is usually when you need them most.
//
// ### Container image
//
// The web client is published to the GitHub Container Registry on every push to `main`:
//
// ```bash
// docker run --rm -p 8080:8080 ghcr.io/hoangsonww/2048-game:latest
// ```
//
// The image is the Node runtime, the static files, and the same `scripts/serve-web.mjs` that `make serve` runs — no bundler, no framework, and nothing installed from npm, because the game has no runtime dependencies. It runs as an unprivileged user and carries a health check.
//
// **A pull request builds the image but never publishes it.** A fork's token cannot write packages, and pushing an image built from unreviewed code to a tag other people pull is not something a green check should do — so the publish step is reachable only from a commit that has already landed on a branch. Every pull request still proves the image builds on both architectures and that the running container serves the game, path traversal included.
//
// ### Building Android without Android Studio
//
// The second image is a pinned JDK 17 and Android SDK 34 toolbox. Mount a checkout and build against it:
//
// ```bash
// docker run --rm -v "$PWD:/src" -w /src/Android-Version/Game2048 \
//     ghcr.io/hoangsonww/2048-game-android:latest ./gradlew assembleDebug
// ```
//
// Or build an APK in one shot, without starting a container:
//
// ```bash
// docker buildx build -f Dockerfile.android --target apk --output out .
// ```
//
// CI does both: it verifies the toolchain inside the image, then builds the debug APK *from* that image and runs the unit tests, so the published toolbox is proven to still build the project rather than merely to contain the binaries. The resulting APK is uploaded as a workflow artifact. `linux/amd64` only — Google ships the Android command-line tools as x86_64 Linux binaries, so an arm64 image would build cleanly and then fail at `aapt2` and `d8`.
//
// **iOS cannot be containerized, and this is not a gap that can be closed.** Docker containers are Linux; Xcode is macOS-only and has no Linux build; and Apple's licence forbids redistributing Xcode. Any one of those three is fatal on its own. iOS builds always require a macOS host.
//
// Supporting automation: **dependency review** blocks pull requests that introduce known-vulnerable dependencies, and the **labeler** applies path-based platform labels automatically. Dependency updates are applied by hand — there is no bot opening upgrade pull requests. Issue forms, ownership rules, release-note categories, contribution guidance, support routing, and the security policy all live under `.github/`.
//
// ---
//
// ## Releases and downloads
//
// Every tagged release carries a build of all three clients, so none of them
// requires a toolchain to try:
//
// | File | What it is |
// | --- | --- |
// | `2048-vX.Y.Z-debug.apk` | Android app — install directly on a device |
// | `2048-vX.Y.Z-ios-unsigned.zip` | Unsigned iOS `.app` for a simulator, or to sign yourself |
// | `2048-vX.Y.Z-web.zip` | The shipping web client — unzip and serve the folder |
// | `SHA256SUMS-ios.txt`, `SHA256SUMS-web.txt` | Checksums for the two zips |
//
// The latest is at [**Releases**](https://github.com/hoangsonww/2048-Game/releases/latest).
// The web client also runs at [hoangsonww.github.io/2048-Game](https://hoangsonww.github.io/2048-Game/)
// with no download at all.
//
// The iOS artifact is unsigned on purpose. Signing needs a provisioning profile
// and a team identifier, neither of which belongs in a public repository, so App
// Store distribution stays outside this pipeline.
//
// ### One version, three clients
//
// `VERSION` at the repository root is the only place the version is edited.
// `scripts/version.sh` propagates it to `package.json`, `versionName` and
// `versionCode` in the Gradle build, and `MARKETING_VERSION` and
// `CURRENT_PROJECT_VERSION` in every Xcode build configuration. `versionCode` is
// derived — `MAJOR * 10000 + MINOR * 100 + PATCH`, so 2.1.3 is 20103 — rather
// than tracked as a second number to forget.
//
// The agreement is enforced, not assumed: `make check` and CI both fail on drift,
// and the release pipeline checks again at the tag before building anything.
// These five fields had drifted four ways at once, which is why the gate exists.
//
// ### Cutting one
//
// Actions → **Cut release** → Run workflow, and pick `patch`, `minor`, or
// `major`. It verifies the tree, bumps and propagates the version, opens a
// changelog section, commits, tags, dispatches the builds at that tag, and then
// confirms a release exists with its artifacts attached before reporting success.
// `dry_run` shows what would happen without pushing anything.
//
// Releasing by hand is no longer a supported path. [`docs/releasing.md`](../docs/releasing.md)
// covers the pipeline, the three non-obvious constraints it works around, and what
// to do when a stage fails.
//
// ---
//
// ## Accessibility
//
// Accessibility is treated as a behavioral requirement, not a finishing touch, and parts of it are covered by automated tests.
//
// - **Keyboard.** The entire web game is playable without a pointer. Arrow keys and WASD move, `F` toggles fullscreen, and every control is reachable by `Tab` with a visible focus indicator.
// - **Screen readers.** Moves, merges, score changes, and end states are announced through a live region on web, through accessibility labels and identifiers on iOS, and through Compose semantics on Android. The board itself is exposed as an explicit accessibility container.
// - **Motion.** Tile animations respect the platform reduced-motion preference and degrade to instant state changes.
// - **Contrast and targets.** Tile and text colors are chosen for readable contrast at every tile value, and interactive targets meet platform minimum sizes.
// - **Iconography.** Every control uses real vector artwork — SVG on web, SF Symbols on iOS, Material vectors on Android — centered by geometry rather than by font metrics. ASCII, emoji, and Unicode glyphs are never used as icons, so nothing depends on a font that may not load.
// - **Layout.** Compact and large breakpoints are both verified, including safe-area insets on iOS and gesture-navigation insets on Android.
//
// ---
//
// ## Privacy and data handling
//
// **Local-first by default.** Without an account, nothing leaves your device.
//
// - No analytics SDK, advertising SDK, or crash reporter.
// - Game state lives in `localStorage` on web, `UserDefaults` on iOS, and `SharedPreferences` on Android — removable by clearing site data or deleting the app.
// - The only non-game outbound request the web client may make is Google Fonts for the display typeface; the app remains fully playable if that request is blocked.
//
// **Optional account.** Creating an account enables cross-device save sync, scores, and leaderboards against the Cloud API. Declining the invitation leaves play unchanged. Details: [docs/privacy.md](../docs/privacy.md) and [docs/backend.md](../docs/backend.md).
//
// ---
//
// ## Web discoverability and PWA install
//
// The web client ships production-grade metadata: canonical and `hreflang` links, Open Graph and Twitter card tags with dedicated share artwork, `schema.org` `WebSite` and `VideoGame` JSON-LD structured data, a complete `sitemap.xml`, `robots.txt` advertising that sitemap, and both `llms.txt` and `llms-full.txt` describing the product in a machine-readable form for language models.
//
// The PWA manifest supplies maskable 192 px and 512 px icons, an SVG favicon with an `.ico` fallback, app shortcuts for "new round" and "how to play", standalone display with `window-controls-overlay` override, and a themed splash color. On Chrome or Edge, use **Install app** in the address bar; on iOS Safari, use **Share → Add to Home Screen**. Once installed the game runs full screen and works entirely offline.
//
// ---
//
// ## Agent-ready development
//
// [`AGENTS.md`](../AGENTS.md) is the shared source of truth for architecture, behavioral invariants, commands, and change discipline. Repository-local skills in `.agents/skills/` provide focused workflows for web, iOS, Android, cross-platform parity, and release readiness, and thin adapters keep Claude Code, GitHub Copilot, Cursor, Gemini CLI, Windsurf, and Codex-compatible harnesses aligned on the same instructions rather than drifting apart.
//
// Skills are task routers, not blanket permission — an agent must still respect the requested scope and preserve unrelated working-tree changes. See [`docs/agent-harness.md`](../docs/agent-harness.md) for the recommended sequence.
//
// ---
//
// ## Troubleshooting
//
// | Symptom | Cause and fix |
// | --- | --- |
// | `npm test` fails on the browser step | Chromium is not installed. Run `npx playwright install chromium`. |
// | `make test-ios` reports no simulator | No available iPhone runtime. Check `xcrun simctl list devices available`, then pin one with `IOS_SIMULATOR_ID=<udid>`. |
// | Gradle cannot find the Android SDK | `ANDROID_HOME` is unset, or `local.properties` is missing. `local.properties` is machine-local and intentionally not committed — Android Studio regenerates it on first sync. |
// | `Android Gradle plugin requires Java 17` on a raw `./gradlew` | Your default JDK is older and the daemon JVM criteria were not picked up. Use `make android-build`, which resolves a JDK 17 explicitly, and confirm `Android-Version/Game2048/gradle/gradle-daemon-jvm.properties` is present. |
// | First Android build is slow | Gradle is downloading its own JDK 17 (~180 MB) and the Gradle distribution. Both are cached; later builds take seconds. |
// | `adb: command not found` | `platform-tools` is not on `PATH`. The `make` targets resolve `adb` from `ANDROID_HOME` automatically — use `make android-run` rather than calling `adb` directly. |
// | `connectedDebugAndroidTest` hangs or loses the hierarchy | An emulator/ADB harness failure rather than an app defect. Check `adb logcat`, restart the emulator without wiping data, and rerun the exact failing test before filing a bug. |
// | Port 8080 already in use | Another server is bound. Stop it, or run the static server on a different port. |
// | The web page looks stale after an edit | The dev server disables caching, but a service-worker-style hard cache in the browser can persist. Hard-reload with `⌘⇧R` / `Ctrl+Shift+R`. |
// | ShellCheck steps are skipped locally | ShellCheck is optional locally but required in CI. Install it (`brew install shellcheck`) to catch shell issues before pushing. |
//
// ---
//
// ## Contributing
//
// Small, focused pull requests are very welcome. Before opening one:
//
// 1. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`AGENTS.md`](../AGENTS.md).
// 2. Keep the game rules consistent across all three clients, or explicitly document an intentional platform difference.
// 3. Use platform-native vector icons — never text glyphs.
// 4. Add a test for behavior changes, or include a clear manual verification note describing exactly what you checked.
// 5. Run `make check` plus the full suite for every platform you touched, and attach screenshots for UI changes.
//
// Issue forms for [bug reports](https://github.com/hoangsonww/2048-Game/issues/new?template=bug_report.yml) and [feature requests](https://github.com/hoangsonww/2048-Game/issues/new?template=feature_request.yml) are available. Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md), and [`SUPPORT.md`](SUPPORT.md) explains where to ask questions.
//
// ---
//
// ## Security
//
// The clients are local-first and play without an account. The optional Cloud API adds auth and sync — see [`SECURITY.md`](SECURITY.md) for the disclosure process. Do not open a public issue for a suspected vulnerability.
//
// ---
//
// ## Citation
//
// If this project is useful in academic work or you want to reference its cross-platform parity approach, citation metadata is provided in [`CITATION.cff`](../CITATION.cff). GitHub renders a ready-to-copy APA and BibTeX citation from that file via the **Cite this repository** button on the repository sidebar.
//
// ---
//
// ## License and credits
//
// Released under the [MIT License](../LICENSE).
//
// Created and maintained by [Son Nguyen](https://github.com/hoangsonww). The original 2048 concept is by Gabriele Cirulli; this is an independent implementation and is not affiliated with or endorsed by the original author.

// SOURCE: docs/architecture.md

// # Architecture
//
// This document is the authoritative description of how the three clients are built and what they must have in common. Read it before changing game rules, state handling, or persistence in any client.
//
// ## Table of contents
//
// - [Design principle](#design-principle)
// - [Runtime boundaries](#runtime-boundaries)
// - [The rules model](#the-rules-model)
// - [The move algorithm](#the-move-algorithm)
// - [Scoring](#scoring)
// - [Tile spawning and injectable randomness](#tile-spawning-and-injectable-randomness)
// - [Undo](#undo)
// - [Terminal states](#terminal-states)
// - [Persistence and state validation](#persistence-and-state-validation)
// - [Application lifecycle](#application-lifecycle)
// - [Sound](#sound)
// - [Server-driven surfaces](#server-driven-surfaces)
// - [Optional cloud layer](#optional-cloud-layer)
// - [Web client](#web-client)
// - [iOS client](#ios-client)
// - [Android client](#android-client)
// - [Web delivery and base paths](#web-delivery-and-base-paths)
// - [Making a parity-safe change](#making-a-parity-safe-change)
//
// ## Design principle
//
// The repository contains three local-first clients and an optional Cloud API. There is **no shared rules runtime** and **no generated cross-platform layer**. Each client is written idiomatically for its platform. Network access is never required to move a tile; accounts and sync live in additive modules documented in [backend.md](backend.md).
//
// That is a deliberate trade. A shared core would guarantee parity mechanically but would force a lowest-common-denominator architecture onto all three platforms and add a build step to a project that otherwise needs none. Instead, parity is maintained by three explicit mechanisms:
//
// 1. **This document plus [`AGENTS.md`](../AGENTS.md)** define the contract in prose precise enough to implement against.
// 2. **Each client independently proves the contract** with its own deterministic rules tests.
// 3. **CI runs all three toolchains on every pull request**, so a parity regression anywhere fails the build.
//
// The cost of this approach is that a rules change must be made three times. That is accepted, and it is why the invariant list below is written to be unambiguous.
//
// ## The same contract, three presentations
//
// Each client renders the same board, score pair, and action bar with native idioms. Pixel identity is not the goal; equivalent capability, hierarchy, and feedback are. Optional cloud chrome (Sign in, leaderboard, guest invite) appears on all three.
//
// | Web | iOS | Android |
// | :---: | :---: | :---: |
// | ![The web client's board, guest invite, and cloud controls](../images/web-version-UI.png) | ![The SwiftUI client with Sign in, leaderboard, and guest banner](../images/IOS-UI.png) | ![The Compose client with Sign in, leaderboard, and guest banner](../images/android-ui.png) |
// | Inline SVG icons | SF Symbols | Material vectors |
//
// ## Runtime boundaries
//
// | Concern | Web | iOS | Android |
// | --- | --- | --- | --- |
// | UI | `index.html`, `Web-Version/style.css` | `GameView.swift`, `ContentView.swift` | `MainActivity.kt`, Compose theme files |
// | Rules engine | `Web-Version/game-engine.js` | `GameViewModel.swift` | `GameViewModel.kt` |
// | State orchestration | `Web-Version/script.js` | `GameViewModel.swift` | `GameViewModel.kt` |
// | Persistence | `localStorage`, key `game2048-state-v2` | `UserDefaults` | `GameStorage.kt` over `SharedPreferences` |
// | Server-driven content | — | `Game-2048/SDUI/` | `sdui/` package |
// | Unit tests | Node.js test runner | XCTest | JUnit 4 |
// | UI tests | Playwright (Chromium) | XCUITest | Compose UI Test |
// | Language | JavaScript (ES modules) | Swift 5 | Kotlin 1.9 |
//
// Only the web client separates the pure engine from the orchestration layer into distinct files. `game-engine.js` is side-effect free and importable from both the browser and Node, which is what allows its coverage to be enforced cheaply. On iOS and Android the equivalent logic lives inside the view model but must remain free of view dependencies so it stays unit-testable without a simulator or emulator.
//
// ## The rules model
//
// Every board is a 4×4 collection whose cells contain either zero (empty) or a positive power of two. Boards are addressed with the origin at the top-left; rows increase downward and columns increase rightward. The web client exposes this exact coordinate system through its `render_game_to_text()` debug hook, and tests depend on it.
//
// ## The move algorithm
//
// A move processes each row or column **in travel order** — the line nearest the destination edge is resolved first — and applies four steps:
//
// 1. Remove empty cells, preserving order.
// 2. Walk the remaining values left to right, merging each adjacent equal pair into a single doubled tile. **A tile that was produced by a merge cannot merge again in the same move.** This is why `[2, 2, 4]` moving left becomes `[4, 4]` and not `[8]`.
// 3. Pad the line back to length four with zeros on the trailing side.
// 4. Write the line back to the board.
//
// After all lines are processed, compare the resulting board with the pre-move board. If they are identical the move was **ineffective**: no tile spawns, the score does not change, and no undo snapshot is created. If they differ the move was **valid** and exactly one new tile spawns.
//
// The comparison against the pre-move board is the single source of truth for move validity. Do not track validity by counting merges or slides separately — that has historically been the source of parity bugs, particularly around moves that slide tiles without merging any.
//
// ## Scoring
//
// The score increases by the value of each **newly created** merged tile. Merging two `4` tiles adds `8`. A move producing two separate merges adds the sum of both results. Sliding without merging adds nothing.
//
// `best` is the maximum score ever achieved and **never decreases** — not on a new game, not on undo, and not when a saved game is discarded as corrupt.
//
// ## Tile spawning and injectable randomness
//
// After a valid move, one tile spawns in a uniformly random empty cell. Its value is `2` with 90 % probability and `4` with 10 % probability.
//
// Every client must allow this randomness to be injected so tests are deterministic:
//
// - Web: the engine accepts a random provider function.
// - iOS: the view model accepts an injected generator; UI tests additionally use launch arguments.
// - Android: the view model accepts an injected generator; instrumentation tests use launch state.
//
// Production code paths must always use unbiased platform randomness. Never ship a seeded or predictable generator as the default.
//
// ## Undo
//
// Undo is strictly **one step**. Before a valid move is applied, the client captures a snapshot containing the exact pre-move board and score. Undo restores that snapshot and then **consumes** it, so undo cannot be pressed twice in a row to walk further back.
//
// An ineffective move must not create a snapshot. Failing to honor that produces the most commonly reported parity bug in this codebase: pressing a direction against a wall, then pressing undo, and watching the board jump back an extra move.
//
// ## Terminal states
//
// **Win.** Presented the first time any tile reaches 2048. The player may dismiss the overlay and continue playing; a persisted continuation flag prevents the win state from being presented again in the same round.
//
// **Game over.** Presented when the board is full **and** no two orthogonally adjacent tiles are equal, since at that point no direction can change the board. Checking fullness alone is insufficient — a full board with an available merge is still playable.
//
// ## Persistence and state validation
//
// Each client persists the board, score, best score, and win-continuation flag after every state change, and restores them at launch.
//
// Restored state is **always validated before use**. A saved payload is rejected if it is malformed JSON, has the wrong board length, contains values that are not zero or a positive power of two, contains a negative score, or is missing required fields. Rejected state is discarded and replaced with a fresh game. The best score is preserved across a discard where it is independently readable.
//
// This matters because saved state is user-writable on every platform — browser dev tools, a jailbroken device, a rooted emulator. A corrupt save must never crash the app or restore an impossible board.
//
// ## Application lifecycle
//
// 1. Restore and validate persisted state, or create a fresh board seeded with two tiles.
// 2. Accept a direction from keyboard, on-screen control, or gesture input.
// 3. Resolve exactly one move atomically, capturing an undo snapshot first when the move is valid.
// 4. Persist board, score, best score, and continuation flag.
// 5. Evaluate the win and game-over predicates and present the matching UI.
//
// Input handling must guarantee **one move per discrete input**. A single continuous drag produces exactly one move, not a stream of them — enforced with a gesture threshold plus a per-gesture latch on all three clients.
//
// ## Sound
//
// Cues are synthesised at runtime on all three clients — no audio assets — and
// mute is a single preference honoured before any audio device is opened.
//
// A cue must be heard **now or not at all**. Each client caps how many voices
// sound at once and drops the excess rather than queueing it, because every
// platform's obvious implementation is a queue that turns a fast run of moves
// into a burst arriving seconds later:
//
// - **Web** builds its `AudioContext` inside the first user gesture and drops any
//   cue scheduled while the context clock is not running. A context created
//   earlier is suspended, and a suspended context's `currentTime` never advances.
// - **iOS** round-robins across a pool of `AVAudioPlayerNode`s, interrupting each,
//   because a single node plays its scheduled buffers strictly in sequence.
// - **Android** keeps one streaming `AudioTrack` open and mixes the sounding
//   voices into it, instead of allocating a track and a thread per cue.
//
// See [ARCHITECTURE.md](../ARCHITECTURE.md#sound-architecture).
//
// ## Server-driven surfaces
//
// Both native clients carry a server-driven UI runtime. The web client does not:
// it is a static page a maintainer can edit and redeploy in seconds, so the
// problem SDUI solves — waiting on store review to change a string — does not
// exist there.
//
// The runtime is described in full in
// [ARCHITECTURE.md](../ARCHITECTURE.md#server-driven-surfaces). What matters when
// changing this code:
//
// - **Rules are never data.** `GameViewModel` on both platforms is untouched by
//   the surface layer, and no payload can reach the board, scoring, merging, or
//   undo.
// - **Every surface needs a native fallback at the call site.** `SurfaceView`
//   takes one as a `@ViewBuilder`; on Android the caller renders its own content
//   when resolution is not `Render`. Adding a surface without a fallback is the
//   one way to make this feature able to break a screen.
// - **Node types are open.** Adding one is additive; changing the meaning of an
//   existing one is a `schemaVersion` bump.
// - **Both payloads must stay identical.** `Game-2048/Surfaces/help.json` and
//   `Android-Version/.../assets/surfaces/help.json` are byte-identical and a test
//   asserts it.
// - **New iOS surface files must be added to the Xcode target.** The project has
//   no synchronised groups, so a file only on disk never compiles.
//
// ## Optional cloud layer
//
// Accounts, cross-device sync, and leaderboards are additive modules on each
// client. The rules engine never imports them; a small bridge
// (`cloudSave` / `applyCloudSave`) converts the board to the flat wire format.
//
// | Concern | Rule |
// | --- | --- |
// | Play without an account | Fully supported; guest prompt is dismissible |
// | Guest and account rounds | Separate storage profiles. Signing in warns, parks the guest round, and loads the account's own; signing out restores the guest round exactly |
// | Career statistics | Come from the account only — never lifted from the device's local round |
// | Credential entry | “Sign in” opens sign-in and “Create account” opens registration. Sign-up confirms the password, every password field has its own reveal control, and closing a form hides them all again |
// | Forgotten passwords | Interim reset: a matching username and email set a new password and revoke every session. Deliberately weak, feature-flagged, and documented as temporary — see [ARCHITECTURE.md](../ARCHITECTURE.md#credential-entry) |
// | Sync conflicts | Prefer the further round; park the other — never last-writer-wins discard |
// | Offline | Moves never wait on the network |
// | In-flight requests | Auth, sync, leaderboard, and sign-out show a spinner and disable the control that started them; the board stays playable |
// | Layout (iOS) | Cloud UI must not push the board into a `ScrollView` |
//
// Authentication and reconciliation are deliberately separate steps. Signing in
// returns a session and nothing more; the game then decides which profile is
// active and asks the cloud layer to adopt the account's round. Only the game
// knows which board is on screen, so only the game can decide what may be
// offered to the server.
//
// Full contract: [backend.md](backend.md). Privacy: [privacy.md](privacy.md).
//
// ## Web client
//
// Static files with no bundler, transpiler, or runtime dependencies. `game-engine.js` is pure and dual-target (browser and Node), which keeps enforced coverage cheap and fast. `script.js` owns DOM wiring, input handling, persistence, and the accessibility live region. Optional `cloud.js` / `account.js` own the account surface.
//
// Both files are covered at 100 % of lines. `script.js` is an IIFE that reads the document once on load and then talks to the page only through the elements it captured, which is exactly what lets `tests/web/helpers/fake-dom.js` stand in for the browser and unit-test it. Keep that property: a controller that reaches back into `document` mid-flight is a controller that can only be tested in a real browser.
//
// Input sources: arrow keys, WASD, `touchstart`/`touchend` swipe on `#gridContainer` with a 28 px threshold, and on-screen direction buttons. `F` toggles fullscreen.
//
// The board sets `touch-action: none`, `html`/`body` set `overscroll-behavior: none`, and a non-passive `touchmove` listener scoped to the board calls `preventDefault()`. The existing touch listeners are passive and cannot, so without that guard a board swipe chains into pull-to-refresh and rubber-band scrolling. A `touchcancel` handler clears the start point; otherwise a cancelled gesture leaves the board suppressing scrolling and measures the next swipe from a stale origin.
//
// The client exposes `window.render_game_to_text()`, a JSON debug snapshot of the coordinate system, board, score, best, undo availability, and available moves. Browser tests and manual verification both rely on it; keep it accurate when state shape changes.
//
// The local development server intentionally disables caching so UI work reloads predictably.
//
// ## iOS client
//
// SwiftUI, targeting iOS 17.4+ for both iPhone and iPad. Uses `UserDefaults` for persistence, `UINotificationFeedbackGenerator`-class haptics, SF Symbols for all control iconography, and accessibility identifiers on every interactive element so XCUITest can drive real flows. Optional cloud code lives in `Game-2048/Cloud/` and must be listed in the Xcode project — same rule as surfaces.
//
// The board is exposed as an explicit accessibility container rather than a pile of individually focusable cells, which is what makes VoiceOver navigation coherent.
//
// Layout is size-responsive rather than fixed — do not reintroduce hard-coded board dimensions.
//
// **The board must never sit inside a scrolling container.** A `ScrollView`'s pan is a UIKit gesture recogniser, so it outranks the board's SwiftUI `DragGesture` outright: every vertical swipe reaches the scroll view and no tile ever moves. Neither `.highPriorityGesture` nor `.scrollBounceBehavior` changes that. The layout is therefore sized to fit the viewport, with `ViewThatFits(in: .vertical)` falling back to a scrolling layout only where the content genuinely cannot fit — very small devices, or the largest accessibility text sizes — where reaching the controls matters more than swipe fidelity. If you add vertical content here, keep the static branch fitting, and check `app.scrollViews` is empty in the UI tests.
//
// ## Android client
//
// Jetpack Compose with Material 3, `minSdk` 24 and `compileSdk`/`targetSdk` 34, Kotlin 1.9 with AGP 8.3.1 on Gradle 8.13. State lives in a `ViewModel`; persistence goes through `GameStorage.kt` over `SharedPreferences`. Optional cloud code lives under `…/cloud/` and uses `HttpURLConnection` with a fake-transport seam for JVM unit tests.
//
// No JDK needs to be installed. `gradle/gradle-daemon-jvm.properties` pins daemon JVM criteria, so Gradle downloads and runs on its own Adoptium JDK 17 matching the host OS and architecture; `scripts/android.sh` additionally prefers a local JDK 17 when one exists.
//
// Grid updates are **immutable** — produce a new board rather than mutating in place. In-place mutation previously broke Compose recomposition and reverse-direction merges simultaneously, and it is the single most important Android-specific constraint in this codebase.
//
// Iconography uses Material vector assets, including the adaptive launcher icon. Compose semantics back the instrumentation tests.
//
// The board's `detectDragGestures` **must consume each `PointerInputChange`**. The root column scrolls vertically, so an unconsumed change is delivered to the parent scroll as well and a board swipe drags the whole screen.
//
// Tile animation mirrors the other clients rather than inventing its own timing: the background colour eases over 180 ms (web's `.cell` transition), a tile that gains a value springs from 82 % to full size (web's `pop` keyframe), values cross-fade through `AnimatedContent` (iOS's `.contentTransition(.numericText())`), and the end panel fades over 250 ms (web's `fade-in`). All of it collapses to instant when the system animation scale is zero, which is Android's equivalent of `prefers-reduced-motion`.
//
// ## Web delivery and base paths
//
// The web app is deployed as static files beneath `/2048-Game/` on GitHub Pages. Canonical URLs, `hreflang` links, the manifest `id`/`start_url`/`scope`, sitemap `<loc>` entries, the `robots.txt` sitemap directive, and Open Graph image URLs must all retain that base path. `scripts/validate-repository.mjs` enforces several of these and will fail the build if they drift.
//
// ## Making a parity-safe change
//
// When you change game rules or user-facing behavior:
//
// 1. Update the invariant list in [`AGENTS.md`](../AGENTS.md) and this document first, so the contract leads the implementation.
// 2. Implement in all three clients, or document explicitly why a platform intentionally differs.
// 3. Add or update the deterministic rules test on each platform.
// 4. Run `make check` plus every affected platform suite.
// 5. Capture and visually inspect screenshots for any changed UI state.
//
// Business rules must never move into view-only code on any platform. If a rule is only reachable by rendering a view, it cannot be unit-tested, and parity stops being verifiable.
