import SwiftUI

@main
struct Game_2048App: App {
    private let viewModel: GameViewModel

    init() {
        let scenario = ProcessInfo.processInfo.environment["GAME2048_UI_TEST_STATE"]
        if let scenario {
            let model = GameViewModel(loadSavedGame: false, randomIndex: { _ in 0 }, randomUnit: { 0 })
            switch scenario {
            case "merge":
                model.setGameForTesting(grid: [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], score: 32)
            case "won":
                model.setGameForTesting(grid: [[2048, 4, 2, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], score: 4096, hasWon: true)
            case "game-over":
                model.setGameForTesting(grid: [[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 2]], score: 512)
            default:
                break
            }
            viewModel = model
        } else {
            viewModel = GameViewModel()
        }
    }

    var body: some Scene { WindowGroup { GameView(viewModel: viewModel).preferredColorScheme(.light) } }
}

// MARK: - Maintainer reference (documentation only)
//
// Contributor and agent operating guide.
//
// This section is intentionally comment-only. The named repository files remain
// canonical; their contents are mirrored here as an in-source reading reference.
// No declaration, executable statement, build setting, or runtime behavior follows.

// SOURCE: AGENTS.md

// # Agent guide for 2048
//
// This file is the source of truth for coding agents working in this repository. Follow the user’s current request first, then the closest scoped `AGENTS.md`, then this guide.
//
// ## Project shape
//
// This repository ships the same 2048 experience in three independent clients:
//
// - Web: static HTML/CSS/JavaScript in `index.html` and `Web-Version/`.
// - iOS: SwiftUI app in `Game-2048/`, with XCTest and XCUITest targets.
// - Android: Jetpack Compose app under `Android-Version/Game2048/`.
//
// The clients do not share runtime code. When game rules or user-facing behavior changes, inspect all three implementations and either preserve parity or document an intentional platform difference.
//
// Read [ARCHITECTURE.md](ARCHITECTURE.md) for the whole-repository picture — the shared behavioural contract, the rules engine, and why there is no shared core. Read [docs/architecture.md](docs/architecture.md) for per-client implementation detail before changing state, persistence, or game rules. Read [docs/testing.md](docs/testing.md) before changing tests or CI. Read [docs/releasing.md](docs/releasing.md) before changing versioning or the release workflows.
//
// ## Commands
//
// - `make help`: list supported workflows.
// - `make check`: fast syntax, repository, shell, SEO, and discovery checks.
// - `make serve`: serve the web app at `http://localhost:8080`. Set `GAME2048_API_BASE_URL` to point it at a locally running Cloud API.
// - `make test-web`: complete deterministic and browser web suite.
// - `make android-run`: build, install, and launch on a device or emulator.
// - `make android-build` / `android-install` / `android-devices` / `android-tasks` / `android-clean`.
// - `make gradle ARGS="<task>"`: run any other Gradle task with a correct JDK.
// - `make test-android`: Android unit tests, lint, and debug APK.
// - `make test-android-device`: include Compose tests on a connected device.
// - `make ios-run`: build, install, and launch on a simulator.
// - `make ios-build` / `ios-boot` / `ios-devices`.
// - `make test-ios`: iOS unit and UI tests on an available simulator.
// - `make test`: run every suite supported by the current host.
// - `make screenshots-web`: capture deterministic desktop/mobile game + cloud UI states and promote into `images/`.
// - `make screenshots-web-qa`: same captures into `output/playwright/latest/` only.
// - `make screenshots-mobile`: capture canonical iOS and Android game + cloud UI states from a booted simulator/emulator and promote into `images/`.
// - `make screenshots-mobile-qa`: same native captures into `output/mobile/` only.
// - `make version`: print the version and verify every client agrees with it.
// - `make version-sync`: rewrite the derived version fields from `VERSION`.
// - `make server-check` / `server-test`: Cloud API OpenAPI validation and unit tests (`server/`).
//
// Never call `adb`, `xcrun`, or `./gradlew` bare from a script or Make target. Use `scripts/android.sh` and `scripts/ios.sh`, which resolve a JDK 17, an `adb` binary, and a simulator UDID. Bare `adb` is not on `PATH` on a default Android Studio install.
//
// Run the smallest relevant checks while iterating and the complete affected-platform suite before handoff. Do not claim an unavailable native runtime passed.
//
// ## Change rules
//
// - Preserve existing user changes in a dirty working tree. Do not reset, discard, or rewrite unrelated work.
// - Treat audit, diagnosis, review, and test-only requests as read-only unless the user asks for implementation.
// - Do not add analytics SDKs, advertising, or mandatory network calls for core play without explicit product direction. The optional Cloud API (`server/`, [docs/backend.md](docs/backend.md)) is the approved account / sync / leaderboard path — keep game rules and the active round local-first.
// - Server-driven surfaces describe **content only**. Rules, styling, and behaviour stay in code, every surface keeps a native fallback, and actions are names the host resolves — never code carried in data. See [ARCHITECTURE.md](ARCHITECTURE.md#server-driven-surfaces).
// - Keep the active round local-first. Validate persisted state (local and cloud) before restoring it.
// - Keep source code deterministic where tests inject a random tile provider.
// - Do not edit generated Xcode project identifiers or Gradle wrapper binaries unless the task requires it.
// - Never commit `local.properties`, signing files, tokens, build output, or local simulator data.
// - `VERSION` is the only place the version is edited. `package.json`, the Gradle
//   build, and the Xcode project are derived from it by `scripts/version.sh`; never
//   edit them directly. Release only through the `Cut release` workflow, never by
//   tagging manually. See [docs/releasing.md](docs/releasing.md).
//
// ## Product invariants
//
// - A valid move compacts tiles, merges equal neighbors once, scores the merged values, and spawns one new `2` or `4`.
// - An ineffective move changes nothing, creates no undo snapshot, and spawns no tile.
// - Undo restores exactly the board and score before the most recent valid move.
// - New game preserves the best score and requires confirmation when a round is active.
// - Reaching 2048 presents a win state and allows continued play. A full board with no merge presents game over.
// - Corrupt or structurally invalid saved state is discarded safely.
// - The guest round and the signed-in round are separate profiles. Signing in
//   warns before taking a round off the screen, parks the guest round untouched,
//   and loads the account's own; signing out restores the guest round exactly,
//   best score included. Career statistics come from the account and are never
//   lifted from local storage. See
//   [ARCHITECTURE.md](ARCHITECTURE.md#guest-and-account-profiles).
// - A control labeled “Sign in” opens sign-in, never sign-up; explicit “Create
//   account” actions open registration. Sign-up confirms the password, every
//   password field has its own reveal control, and closing a form hides them again. Password recovery is an
//   interim username + email check that revokes every session — read the
//   security note on the endpoint before extending it. See
//   [ARCHITECTURE.md](ARCHITECTURE.md#credential-entry).
// - Sound cues are heard now or dropped. No client may queue a cue it cannot
//   play immediately — a backlog that arrives seconds later is worse than
//   silence. See [ARCHITECTURE.md](ARCHITECTURE.md#sound-architecture).
//
// ## UI and accessibility
//
// - Use SVG on web, SF Symbols on iOS, and Material vector icons on Android. Never use ASCII, emoji, or Unicode glyphs as button icons.
// - Keep icon artwork centered by geometry and layout, with an accessible name on the enclosing control.
// - Support keyboard and touch on web, native swipes on mobile, visible focus, reduced motion, and readable contrast.
// - A board swipe belongs to the board. It must never scroll, bounce, or pan the surrounding screen, and every direction must register a move. Each client enforces this differently: web sets `touch-action: none` plus a non-passive `touchmove` guard, iOS keeps the board out of any scrolling container, and Android consumes each pointer change so the parent scroll never sees it. All three are covered by tests; see [docs/testing.md](docs/testing.md#gesture-ownership).
// - Check compact and large layouts. UI changes require screenshots of affected states and manual visual inspection.
//
// ## Documentation and generated artifacts
//
// Keep `.github/README.md`, relevant files in `docs/`, `llms.txt`, and agent guidance accurate when commands or architecture change. Store repeatable utilities in `scripts/`; place local QA output under `output/`. Do not hand-edit generated coverage or build products.
//
// ## Repository-local skills
//
// Load the narrowest matching skill from `.agents/skills/`:
//
// - `2048-web-development`: browser UI, engine, accessibility, PWA, or SEO work.
// - `2048-ios-development`: SwiftUI, XCTest, persistence, or simulator work.
// - `2048-android-development`: Compose, ViewModel, Gradle, or emulator work.
// - `2048-cross-platform-parity`: behavior spanning two or more clients.
// - `2048-release-readiness`: final validation, screenshots, documentation, and release checks.

// SOURCE: .github/CONTRIBUTING.md

// # Contributing
//
// Thank you for improving 2048. Contributions of every size are welcome — a typo fix is as valid as a new platform feature.
//
// The one thing this project asks above all else: **keep the three clients behaving identically.** Everything below exists to make that easy rather than tedious.
//
// ## Table of contents
//
// - [Quick start](#quick-start)
// - [What to work on](#what-to-work-on)
// - [The behavior contract](#the-behavior-contract)
// - [Making a change](#making-a-change)
// - [Code style](#code-style)
// - [UI and accessibility changes](#ui-and-accessibility-changes)
// - [Testing requirements](#testing-requirements)
// - [Commit hooks](#commit-hooks)
// - [Commit messages](#commit-messages)
// - [Pull requests](#pull-requests)
// - [What not to commit](#what-not-to-commit)
// - [Review expectations](#review-expectations)
//
// ## Quick start
//
// 1. Install Node.js 22. Android work additionally needs the Android SDK 34; iOS work needs Xcode on macOS.
// 2. Run `make setup`, or reopen the repository in its dev container.
// 3. Run `make doctor` to see which platform toolchains this machine supports.
// 4. Run `make help` for the full command list.
// 5. Create a branch and make the smallest coherent change.
//
// **You do not need to install or configure a JDK.** Gradle provisions its own JDK 17 from the committed daemon JVM criteria, and `scripts/android.sh` resolves one up front, so Android builds work even when your default `java` is a different version.
//
// Every platform has one-command entry points:
//
// ```bash
// make serve          # web app at localhost:8080
// make android-run    # build, install, and launch on a device or emulator
// make ios-run        # build, install, and launch on a simulator
// ```
//
// On Linux, iOS is reported as unavailable rather than silently skipped or emulated — that is intentional. Never report a suite as passing when its toolchain was not present.
//
// ## What to work on
//
// Good first contributions:
//
// - Bug fixes with a reproducible case, especially parity bugs where one client behaves differently from the other two
// - Accessibility improvements — contrast, focus order, screen-reader labels, touch targets
// - Test coverage for an uncovered branch
// - Documentation corrections and clarifications
//
// Please open an issue before starting on:
//
// - New gameplay features or rule changes
// - Board sizes other than 4×4
// - Anything that adds a runtime dependency, a build step, or a network call
//
// The web client is deliberately dependency-free and buildless. Proposals that change that need a discussion first, not a pull request first.
//
// ## The behavior contract
//
// Every client must satisfy all of these. They are the definition of "correct" in this repository:
//
// - A valid move shifts all tiles, merges each tile **at most once per move**, updates the score by the merged values, and spawns exactly one `2` (90 %) or `4` (10 %).
// - An ineffective move changes nothing — no score change, no new tile, **no undo snapshot**.
// - Undo restores exactly the board and score from immediately before the last valid move, and is strictly one step.
// - New game preserves the best score and requires confirmation while a round is in progress.
// - Reaching 2048 offers both a fresh game and continued play. A locked board offers a fresh game.
// - Invalid persisted data is validated, rejected, and discarded safely rather than restored or crashed on.
//
// Any intentional platform difference must be stated explicitly in the pull-request description. The full rationale and algorithm detail live in [`docs/architecture.md`](../docs/architecture.md).
//
// ## Making a change
//
// For a rules or behavior change, work in this order:
//
// 1. **Update the contract first** — [`AGENTS.md`](../AGENTS.md) and [`docs/architecture.md`](../docs/architecture.md) — so the specification leads the code.
// 2. **Implement in all three clients**, or document why one intentionally differs.
// 3. **Add or update the deterministic test on each platform.**
// 4. **Run `make check`** plus the complete suite for every platform you touched.
// 5. **Capture screenshots** for any changed UI state and look at them.
//
// For a single-platform change (a web-only layout fix, an iOS-only gesture tweak), steps 2 and 3 narrow to that platform — but confirm first that the change genuinely has no cross-client implication.
//
// ## Code style
//
// There is no autoformatter enforced in CI, so match the surrounding code rather than introducing a new style:
//
// - `.editorconfig` defines indentation and line endings — most editors apply it automatically.
// - **Web:** plain ES modules, no transpilation, no runtime dependencies. Keep `game-engine.js` pure and side-effect free so it stays testable from Node.
// - **iOS:** idiomatic SwiftUI. Keep game logic in the view model, not the view.
// - **Android:** idiomatic Compose with a `ViewModel`. **Board updates must be immutable** — produce a new board rather than mutating in place. In-place mutation has previously broken recomposition and reverse-direction merges at the same time.
// - **Shell:** must pass ShellCheck, which CI enforces.
// - Match the existing comment density. This codebase comments *why*, not *what*.
//
// ## UI and accessibility changes
//
// This is the visual target. Match its density, iconography, and hierarchy rather than introducing a new style:
//
// | Web | iOS | Android |
// | :---: | :---: | :---: |
// | ![The web client's board and controls](../images/web-version-UI.png) | ![The iOS client's board and controls](../images/IOS-UI.png) | ![The Android client's board and controls](../images/android-ui.png) |
//
// Use SVG on web, SF Symbols on iOS, and Material vectors on Android. **Never use Unicode arrows, emoji, or text glyphs as interface icons** — they depend on fonts that may not load and they cannot be centered reliably.
//
// Icons must be centered by geometry and layout, not by font metrics, and the enclosing control must carry an accessible name.
//
// Before submitting, check:
//
// - Compact and wide layouts
// - Keyboard focus order and visible focus indicators
// - Accessible names on every control
// - Touch-target sizes
// - Contrast at every tile value, including high-value tiles
// - Dynamic type / text scaling
// - Reduced-motion behavior
// - Safe areas on iOS, gesture-navigation insets on Android
// - A clean browser console or native log — visible correctness with console errors is still a failure
//
// Attach before/after screenshots for anything visible.
//
// ## Testing requirements
//
// Behavior changes need either a test or a clear manual verification note describing exactly what you checked and on what device.
//
// - Rules behavior belongs in the **deterministic** suite on each platform.
// - User-flow behavior belongs in the platform UI suite, asserting a user-visible outcome rather than re-deriving the rules.
// - **Inject randomness.** Never write a test that depends on real random spawning.
// - Confirm your test fails before the fix and passes after. A test that never failed has proven nothing.
// - **Every platform gates coverage, and all three currently sit well above their floor** (web 100 %, iOS 95.5 %, Android 97.6 %). Web is gated by `c8` at 100 % statements/lines/functions and 95 % branches over all of `Web-Version/`; iOS at 90 % of the app target, read from the `.xcresult` by `scripts/test-ios.sh`; Android at 90 % lines and 85 % branches of the Kotlin engine and storage, enforced by JaCoCo. If you add code, add the tests that keep it above the line — lowering a threshold is not an acceptable fix.
// - Two invariants that catch people writing their first test here: a valid move **always spawns a tile**, so assert the cells the move produced rather than a whole row; and an ineffective move **persists nothing**, so assert the move was accepted before checking what was stored.
// - On iOS, add new test files to the `Game-2048Tests` target in the Xcode project. The project has no synchronised file groups, so a file only on disk never compiles and never runs.
// - Server-driven surfaces describe **content only**. If you add a node type, add it to both native clients, keep the two bundled payloads byte-identical, and never remove a call site's native fallback — a surface that can blank a screen is the one thing that design prevents.
//
// Full detail, including how to tell a real defect from a flaky emulator, is in [`docs/testing.md`](../docs/testing.md).
//
// ## Commit hooks
//
// `npm install` activates Husky:
//
// - **pre-commit** runs the fast repository checks (`make check`)
// - **pre-push** runs the full web suite
//
// Python users can install equivalent hooks instead:
//
// ```bash
// pre-commit install --install-hooks -t pre-commit -t pre-push
// ```
//
// If a hook blocks you for an unrelated pre-existing failure, say so in the pull request rather than bypassing it silently.
//
// ## Commit messages
//
// Write a short imperative subject line describing the effect, not the mechanics:
//
// ```
// Fix undo restoring an extra move after a blocked swipe
// Add reduced-motion handling to Compose tile animations
// Document the single-merge rule in architecture.md
// ```
//
// Explain *why* in the body when the reason is not obvious from the diff. Reference the issue number when there is one.
//
// ## Pull requests
//
// - Complete the pull-request template.
// - Keep it focused. One logical change per pull request reviews far faster than five bundled together.
// - List the exact validation commands you ran and their results.
// - State plainly which suites you could **not** run and why (no macOS, no emulator). This is expected and fine — quietly omitting it is not.
// - Attach screenshots for UI changes.
//
// CI must pass for web, iOS, Android JVM/lint/build, and Android emulator flows. All four jobs are visible independently, so a failure points straight at the responsible platform.
//
// ## What not to commit
//
// `.gitignore` covers these, but do not force-add past it:
//
// - `local.properties`, SDK paths, or any machine-local configuration
// - Build output — APKs, `.app` bundles, `DerivedData/`, `build/`, `coverage/`
// - Credentials, tokens, signing keys, keystores, or provisioning profiles
// - `output/` QA artifacts and screenshots — these are local verification evidence, reproducible with `make test` and `make screenshots-web`
// - IDE state beyond the shared module descriptors
// - Scratch notes and working files
//
// ## Review expectations
//
// Reviews focus on correctness, cross-client parity, accessibility, and test coverage — roughly in that order. Expect questions about parity on anything touching game rules; that is the project's core constraint, not reviewer pedantry.
//
// Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). Questions are welcome in [Discussions](https://github.com/hoangsonww/2048-Game/discussions), and [`SUPPORT.md`](SUPPORT.md) explains where each kind of request belongs.

// SOURCE: .github/CODE_OF_CONDUCT.md

// # Code of Conduct
//
// ## Our Pledge
//
// In the interest of fostering an open and welcoming environment, we as contributors and maintainers pledge to making participation in our project and our community a harassment-free experience for everyone, regardless of age, body size, disability, ethnicity, sex characteristics, gender identity and expression, level of experience, education, socio-economic status, nationality, personal appearance, race, religion, or sexual identity and orientation.
//
// ## Our Standards
//
// Examples of behavior that contributes to creating a positive environment include:
//
// - Using welcoming and inclusive language
// - Being respectful of differing viewpoints and experiences
// - Gracefully accepting constructive criticism
// - Focusing on what is best for the community
// - Showing empathy towards other community members
//
// Examples of unacceptable behavior by participants include:
//
// - The use of sexualized language or imagery and unwelcome sexual attention or advances
// - Trolling, insulting/derogatory comments, and personal or political attacks
// - Public or private harassment
// - Publishing others' private information, such as a physical or electronic address, without explicit permission
// - Other conduct which could reasonably be considered inappropriate in a professional setting
//
// ## Our Responsibilities
//
// Project maintainers are responsible for clarifying the standards of acceptable behavior and are expected to take appropriate and fair corrective action in response to any instances of unacceptable behavior.
//
// Project maintainers have the right and responsibility to remove, edit, or reject comments, commits, code, wiki edits, issues, and other contributions that are not aligned to this Code of Conduct, or to ban temporarily or permanently any contributor for other behaviors that they deem inappropriate, threatening, offensive, or harmful.
//
// ## Scope
//
// This Code of Conduct applies both within project spaces and in public spaces when an individual is representing the project or its community. Examples of representing a project or community include using an official project e-mail address, posting via an official social media account, or acting as an appointed representative at an online or offline event. Representation of a project may be further defined and clarified by project maintainers.
//
// ## Enforcement
//
// Instances of abusive, harassing, or otherwise unacceptable behavior may be reported privately through the repository's [security advisory form](https://github.com/hoangsonww/2048-Game/security/advisories/new) with “Code of Conduct” in the title. All complaints will be reviewed and investigated, and maintainers will protect the reporter's confidentiality as far as reasonably possible.
//
// Project maintainers who do not follow or enforce the Code of Conduct in good faith may face temporary or permanent repercussions as determined by other members of the project's leadership.
//
// ## Attribution
//
// This Code of Conduct is adapted from the [Contributor Covenant](https://www.contributor-covenant.org), version 1.4, available at [https://www.contributor-covenant.org/version/1/4/code-of-conduct.html](https://www.contributor-covenant.org/version/1/4/code-of-conduct.html).
//
// For answers to common questions about this code of conduct, see [https://www.contributor-covenant.org/faq](https://www.contributor-covenant.org/faq).
//
// ---

// SOURCE: .github/SUPPORT.md

// # Support
//
// This is a free, open-source project maintained in spare time. There is no paid support channel — but questions and reports are genuinely welcome, and routing them to the right place gets them answered faster. Play is local-first; the optional Cloud API (accounts, sync, leaderboards) is documented in [docs/backend.md](../docs/backend.md).
//
// ## Where to go
//
// | What you have | Where it goes |
// | --- | --- |
// | A reproducible bug | [Bug report form](https://github.com/hoangsonww/2048-Game/issues/new?template=bug_report.yml) |
// | An idea or improvement | [Feature request form](https://github.com/hoangsonww/2048-Game/issues/new?template=feature_request.yml) |
// | A setup, build, or development question | [GitHub Discussions](https://github.com/hoangsonww/2048-Game/discussions) |
// | A suspected security vulnerability | [Private security advisory](https://github.com/hoangsonww/2048-Game/security/advisories/new) — **never** a public issue |
// | A question about contributing | [`CONTRIBUTING.md`](CONTRIBUTING.md), then Discussions |
//
// ## Before opening an issue
//
// A few minutes here usually saves a round trip:
//
// 1. **Search existing issues**, including closed ones. Parity bugs in particular tend to recur under different descriptions.
// 2. **Check [Troubleshooting](README.md#troubleshooting)** in the README — it covers the common build and toolchain failures (missing Chromium, no simulator, `ANDROID_HOME` unset, port 8080 in use).
// 3. **Run `make doctor`** if the problem is environmental. Its output tells you and us which toolchains are actually present.
// 4. **Confirm which client is affected.** The web, iOS, and Android apps share no runtime code, so "2048 is broken" is three different investigations.
//
// ## What makes a good bug report
//
// - The affected client — web, iOS, or Android — and the version or commit
// - Platform details: browser and version, or iOS/Android version and device or simulator model
// - Exact steps to reproduce, ideally starting from a fresh game
// - What you expected versus what happened
// - A screenshot or short recording for anything visual
// - Browser console output or native crash log if there is any
//
// For rules and gameplay bugs, the board state matters enormously. On the web client, paste the output of `render_game_to_text()` from the browser console — it captures the exact board, score, and available moves in one line, which is far more useful than a description of the board.
//
// ## Response expectations
//
// This is a spare-time project, so response times vary. Actionable reports with clear reproduction steps get looked at first. Security reports are prioritized above everything else.
//
// An issue may be closed as informational if it is a generic automated scan result with no demonstrated impact, a question already answered in the documentation, or a request that conflicts with the project's stated constraints — local-first play, no analytics or advertising SDKs, no mandatory network for a move, and no runtime npm dependencies on the static web client.
//
// ## Never post in public
//
// Credentials, tokens, signing keys, provisioning profiles, or personal information. If you have already posted something sensitive, delete it and rotate the secret — deleted GitHub content can persist in caches and notification emails.

// SOURCE: .github/PULL_REQUEST_TEMPLATE.md

// ## Summary
//
// <!-- Explain the user-visible outcome and why this change is needed. -->
//
// ## Platforms affected
//
// - [ ] Web
// - [ ] iOS / SwiftUI
// - [ ] Android / Jetpack Compose
// - [ ] Repository tooling or documentation only
//
// ## Validation
//
// <!-- List the exact commands and manual flows you ran. -->
//
// - [ ] `make check`
// - [ ] Relevant automated tests pass
// - [ ] UI changes were checked at affected viewport/device sizes
// - [ ] Accessibility labels, focus, touch targets, and reduced motion were considered
// - [ ] Screenshots or recordings are attached for visual changes
//
// ## Cross-platform parity
//
// <!-- Describe any intentional behavioral or visual differences. Write “Not applicable” when appropriate. -->
//
// ## Risk and rollback
//
// <!-- Note persistence/schema changes, migration concerns, or a simple rollback plan. -->
//
// ## Checklist
//
// - [ ] The change is focused and contains no unrelated generated files
// - [ ] Tests cover new behavior or the omission is explained
// - [ ] Documentation and agent guidance remain accurate
// - [ ] No secrets, signing credentials, or machine-local paths are committed

// SOURCE: .github/ISSUE_TEMPLATE/bug_report.yml

// name: Bug report
// description: Report reproducible incorrect behavior in one or more 2048 clients.
// title: "[Bug]: "
// labels: [bug, needs-triage]
// body:
//   - type: markdown
//     attributes:
//       value: Thanks for helping improve the project. Please avoid including private data or signing credentials.
//   - type: dropdown
//     id: platform
//     attributes:
//       label: Platform
//       options:
//         - Web — desktop
//         - Web — mobile
//         - iOS / iPadOS
//         - Android
//         - Repository tooling or CI
//         - Multiple platforms
//     validations:
//       required: true
//   - type: input
//     id: environment
//     attributes:
//       label: Environment
//       description: Browser and version, device model, OS version, or CI run link.
//       placeholder: Safari 18 on iPhone 16 / Android 14 Pixel 7 / Node 22
//     validations:
//       required: true
//   - type: textarea
//     id: steps
//     attributes:
//       label: Reproduction steps
//       placeholder: |
//         1. Start a new game
//         2. Swipe left
//         3. …
//     validations:
//       required: true
//   - type: textarea
//     id: expected
//     attributes:
//       label: Expected behavior
//     validations:
//       required: true
//   - type: textarea
//     id: actual
//     attributes:
//       label: Actual behavior
//     validations:
//       required: true
//   - type: textarea
//     id: evidence
//     attributes:
//       label: Screenshots, logs, or saved-state details
//       description: Drag files here. Remove tokens, personal data, and local absolute paths first.
//   - type: checkboxes
//     id: checks
//     attributes:
//       label: Checks
//       options:
//         - label: I searched existing issues for this problem.
//           required: true
//         - label: I can reproduce this on the latest default branch.
//           required: true

// SOURCE: .github/ISSUE_TEMPLATE/feature_request.yml

// name: Feature request
// description: Propose a focused improvement to gameplay, accessibility, UI, or tooling.
// title: "[Feature]: "
// labels: [enhancement, needs-triage]
// body:
//   - type: dropdown
//     id: scope
//     attributes:
//       label: Primary scope
//       options:
//         - All game clients
//         - Web
//         - iOS / SwiftUI
//         - Android / Jetpack Compose
//         - Accessibility
//         - Documentation or developer experience
//     validations:
//       required: true
//   - type: textarea
//     id: problem
//     attributes:
//       label: Problem or opportunity
//       description: Describe the user need before proposing implementation details.
//     validations:
//       required: true
//   - type: textarea
//     id: outcome
//     attributes:
//       label: Desired outcome
//       description: Explain the observable behavior and how success could be verified.
//     validations:
//       required: true
//   - type: textarea
//     id: alternatives
//     attributes:
//       label: Alternatives and platform differences
//       description: Note simpler options and any intentional native-platform differences.
//   - type: checkboxes
//     id: checks
//     attributes:
//       label: Checks
//       options:
//         - label: I searched existing issues and discussions for similar requests.
//           required: true

// SOURCE: .github/ISSUE_TEMPLATE/config.yml

// blank_issues_enabled: false
// contact_links:
//   - name: Security vulnerability
//     url: https://github.com/hoangsonww/2048-Game/security/advisories/new
//     about: Privately report a security issue instead of opening a public issue.
//   - name: Usage and development help
//     url: https://github.com/hoangsonww/2048-Game/discussions
//     about: Ask setup and contribution questions in GitHub Discussions.

// SOURCE: .github/copilot-instructions.md

// # GitHub Copilot repository instructions
//
// Follow `AGENTS.md` for architecture, product invariants, validation, and UI conventions. This is a three-client 2048 implementation: inspect web, SwiftUI, and Compose equivalents before changing shared behavior. Use `make check` and the affected `make test-*` target. Use only SVG, SF Symbols, or Material vector icons for controls.

// SOURCE: CLAUDE.md

// # Claude Code instructions
//
// @AGENTS.md
//
// Treat `AGENTS.md` as the repository source of truth. Reusable workflows are in `.agents/skills/`; Claude-compatible adapters in `.claude/skills/` point to the same instructions. Prefer `make` and `scripts/` entry points over inventing one-off commands.

// SOURCE: GEMINI.md

// # Gemini CLI instructions
//
// Read and follow `AGENTS.md` before editing. Use the repository-local skills in `.agents/skills/` when their descriptions match the task, and use `make help` for supported commands. Preserve cross-platform game behavior and never substitute text glyphs for interface icons.
