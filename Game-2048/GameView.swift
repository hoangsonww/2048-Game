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
