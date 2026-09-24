# 2048, Built Three Ways

A polished, accessible, **local-first** 2048 puzzle shipped as **three independent native clients** — a dependency-free progressive web app, a SwiftUI iOS app, and a Jetpack Compose Android app — plus an optional Cloud API for accounts, cross-device save sync, and leaderboards. The clients share no runtime code, yet every one of them is held to the same documented set of behavioral invariants and verified by continuous integration. A move never requires the network.

[![Cross-platform CI](https://github.com/hoangsonww/2048-Game/actions/workflows/ci.yml/badge.svg)](https://github.com/hoangsonww/2048-Game/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/hoangsonww/2048-Game?display_name=tag&sort=semver)](https://github.com/hoangsonww/2048-Game/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Play online](https://img.shields.io/badge/Play-online-0E8A16)](https://the-2048.netlify.app)

**Clients**

![JavaScript](https://img.shields.io/badge/JavaScript-F7DF1E?logo=javascript&logoColor=black)
![HTML5](https://img.shields.io/badge/HTML5-E34F26?logo=html5&logoColor=white)
![CSS](https://img.shields.io/badge/CSS-663399?logo=css&logoColor=white)
![PWA](https://img.shields.io/badge/PWA-5A0FC8?logo=pwa&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-0071E3?logo=swift&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-17.4%2B-000000?logo=ios&logoColor=white)
![SF Symbols](https://img.shields.io/badge/SF%20Symbols-native-000000?logo=apple&logoColor=white)
![Kotlin](https://img.shields.io/badge/Kotlin-1.9-7F52FF?logo=kotlin&logoColor=white)
![Android](https://img.shields.io/badge/Android-SDK%2034-3DDC84?logo=android&logoColor=white)
![AndroidX](https://img.shields.io/badge/AndroidX-Core%20%2B%20Lifecycle-3DDC84?logo=android&logoColor=white)
![Jetpack Compose](https://img.shields.io/badge/Jetpack%20Compose-4285F4?logo=jetpackcompose&logoColor=white)
![Material Design 3](https://img.shields.io/badge/Material%20Design-3-757575?logo=materialdesign&logoColor=white)
![Server-driven UI](https://img.shields.io/badge/Server--driven%20UI-iOS%20%2B%20Android-5A0FC8)

**Cloud API**

![Node.js](https://img.shields.io/badge/Node.js-22%2B-5FA04E?logo=nodedotjs&logoColor=white)
![Express](https://img.shields.io/badge/Express-5-000000?logo=express&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-Atlas-47A248?logo=mongodb&logoColor=white)
![Mongoose](https://img.shields.io/badge/Mongoose-8-880000?logo=mongoose&logoColor=white)
![JSON Web Tokens](https://img.shields.io/badge/Auth-JWT-000000?logo=jsonwebtokens&logoColor=white)
![bcryptjs](https://img.shields.io/badge/Passwords-bcryptjs-3381A2)
![Zod](https://img.shields.io/badge/Validation-Zod-3E67B1?logo=zod&logoColor=white)
![Helmet, CORS, rate limits, compression](https://img.shields.io/badge/HTTP-Helmet%20%C2%B7%20CORS%20%C2%B7%20rate%20limits%20%C2%B7%20compression-5A29E4)
![OpenAPI](https://img.shields.io/badge/OpenAPI-3.1-6BA539?logo=openapiinitiative&logoColor=white)
![API reference](https://img.shields.io/badge/API%20docs-js--yaml%20%C2%B7%20Swagger%20UI%20%C2%B7%20Redoc%20%C2%B7%20Scalar-85EA2D?logo=swagger&logoColor=black)

**Build and quality**

![Playwright](https://img.shields.io/badge/Playwright-Chromium-2EAD33?logo=playwright&logoColor=white)
![c8](https://img.shields.io/badge/Web%20coverage-c8-4B8BF5?logo=v8&logoColor=white)
![Xcode](https://img.shields.io/badge/Xcode-15.3%2B-147EFB?logo=xcode&logoColor=white)
![XCTest](https://img.shields.io/badge/XCTest-XCUITest-1B6AC6?logo=swift&logoColor=white)
![Gradle](https://img.shields.io/badge/Gradle-8.13-02303A?logo=gradle&logoColor=white)
![Java](https://img.shields.io/badge/Build%20JDK-17-ED8B00?logo=openjdk&logoColor=white)
![JUnit](https://img.shields.io/badge/JUnit-4-25A162?logo=junit5&logoColor=white)
![Android UI tests](https://img.shields.io/badge/Android%20tests-Espresso%20%C2%B7%20Compose%20UI-3DDC84?logo=android&logoColor=white)
![JaCoCo](https://img.shields.io/badge/Android%20coverage-JaCoCo-CB3F37)
![Supertest](https://img.shields.io/badge/API%20tests-Supertest-0E8A16)
![Husky and pre-commit](https://img.shields.io/badge/Git%20hooks-Husky%20%C2%B7%20pre--commit-F05032?logo=git&logoColor=white)
![Make, Bash, ShellCheck](https://img.shields.io/badge/Automation-Make%20%C2%B7%20Bash%20%C2%B7%20ShellCheck-4EAA25?logo=gnubash&logoColor=white)

**Delivery**

![npm](https://img.shields.io/badge/npm-package%20scripts-CB3837?logo=npm&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-multi--stage-2496ED?logo=docker&logoColor=white)
![Dev Containers](https://img.shields.io/badge/Dev%20Containers-ready-007ACC?logo=docker&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-CI%20%2B%20releases-2088FF?logo=githubactions&logoColor=white)
![GitHub Pages](https://img.shields.io/badge/GitHub%20Pages-web-222222?logo=githubpages&logoColor=white)
![Netlify](https://img.shields.io/badge/Netlify-web-00C7B7?logo=netlify&logoColor=white)
![Vercel](https://img.shields.io/badge/Vercel-Cloud%20API-000000?logo=vercel&logoColor=white)

**[▶ Play the web version](https://the-2048.netlify.app)** · [Download the apps](https://github.com/hoangsonww/2048-Game/releases/latest) · [Cloud API docs](https://game-2048-cloud-api.vercel.app/docs) · [Rules and strategy](https://hoangsonww.github.io/2048-Game/Web-Version/about.html) · [Report an issue](https://github.com/hoangsonww/2048-Game/issues) · [Contributing](.github/CONTRIBUTING.md) · [Security policy](.github/SECURITY.md)

---

## Table of contents

- [Why this project exists](#why-this-project-exists)
- [Screenshots](#screenshots)
- [Feature matrix](#feature-matrix)
- [How to play](#how-to-play)
- [Controls](#controls)
- [Behavioral invariants](#behavioral-invariants)
- [Architecture](#architecture)
- [Cloud API](#cloud-api)
- [Server-driven surfaces](#server-driven-surfaces)
- [Repository map](#repository-map)
- [Getting started](#getting-started)
- [Run the web app](#run-the-web-app)
- [Run the iOS app](#run-the-ios-app)
- [Run the Android app](#run-the-android-app)
- [Command reference](#command-reference)
- [Testing and quality gates](#testing-and-quality-gates)
- [Continuous integration](#continuous-integration)
- [Releases and downloads](#releases-and-downloads)
- [Accessibility](#accessibility)
- [Privacy and data handling](#privacy-and-data-handling)
- [Web discoverability and PWA install](#web-discoverability-and-pwa-install)
- [Agent-ready development](#agent-ready-development)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Security](#security)
- [Citation](#citation)
- [License and credits](#license-and-credits)

---

## Why this project exists

2048 is a small enough game that its rules fit in a paragraph, which makes it an unusually good vehicle for a harder question: **how do you keep three separately written native clients behaving identically, without a shared runtime, a cross-platform framework, or a code generator?**

This repository is the worked answer. There is no React Native layer, no Kotlin Multiplatform module, no WebView wrapper. Each client is idiomatic for its platform — vanilla ES modules on the web, SwiftUI with `@Observable`-style view models on iOS, Compose with a `ViewModel` on Android — and parity is maintained by three deliberate mechanisms instead:

1. **A written invariant contract.** [`ARCHITECTURE.md`](ARCHITECTURE.md), [`AGENTS.md`](AGENTS.md), and [`docs/architecture.md`](docs/architecture.md) define the exact rules every client must satisfy, down to edge cases like "an ineffective move must not spawn a tile."
2. **Per-client deterministic rules tests.** Each platform independently proves the same behavior list against its own engine, with randomness injected so results are reproducible.
3. **A CI pipeline that runs all three toolchains on every pull request.** A parity regression in any one client fails the build.

The result is a codebase where you can read one platform's implementation in isolation and still trust it matches the others.

---

## Screenshots

The same experience on all three clients. `make screenshots-web` captures the browser states; `make screenshots-mobile` drives a booted iPhone simulator and Android emulator. Both commands promote the reviewed canonical set into `images/`.

| Web | iOS | Android |
| :---: | :---: | :---: |
| ![2048 web app with guest invite, Sign in, leaderboard control, and 4×4 board](images/web-version-UI.png) | ![2048 SwiftUI app on iPhone with Sign in, leaderboard, help, and guest sync banner](images/IOS-UI.png) | ![2048 Jetpack Compose app on Pixel with Sign in, leaderboard, and guest account banner](images/android-ui.png) |

### Web states

| Mobile layout | Win | Game over |
| :---: | :---: | :---: |
| ![The web game at a 390px mobile width with on-screen direction controls](images/web-mobile-gameplay.png) | ![The win overlay after reaching 2048, offering a new game or continued play](images/web-win.png) | ![The game-over overlay on a full board with no available merges](images/web-loss.png) |

| New-game confirmation | Rules and strategy |
| :---: | :---: |
| ![The restart confirmation dialog warning that the current round will be replaced](images/web-restart-dialog.png) | ![The About page describing the rules, strategy, and project details](images/web-about.png) |

### Optional cloud surfaces

Guest play, auth, sync, and leaderboards — local-first; an account is never required.

| Guest invite (desktop) | Create account | Sign in |
| :---: | :---: | :---: |
| ![Guest banner inviting account creation above the board](images/web-cloud-guest.png) | ![Create-account dialog with username, email, and password](images/web-cloud-signup.png) | ![Sign-in dialog with username-or-email and password](images/web-cloud-signin.png) |

| Handover warning | Reset password | |
| :---: | :---: | :---: |
| ![Dialog warning that signing in sets the current round aside](images/web-cloud-handover.png) | ![Reset dialog asking for username, email, and a new password twice](images/web-cloud-reset.png) | |

| Signed in | Leaderboard | Account panel |
| :---: | :---: | :---: |
| ![Signed-in header and cloud sync status under the board](images/web-cloud-signed-in.png) | ![Leaderboard dialog with Today / This week / All time periods](images/web-cloud-leaderboard.png) | ![Account panel with profile summary, sync time, and sign out](images/web-cloud-account.png) |

| Mobile guest | Mobile create account | Android create account |
| :---: | :---: | :---: |
| ![Mobile layout with guest invite and on-screen controls](images/web-cloud-mobile-guest.png) | ![Mobile create-account dialog](images/web-cloud-mobile-signup.png) | ![Android Compose create-account bottom sheet](images/android-cloud-signup.png) |

| Android guest | Android leaderboard | Android sign in |
| :---: | :---: | :---: |
| ![Android guest banner above the board](images/android-cloud-guest.png) | ![Android leaderboard bottom sheet](images/android-cloud-leaderboard.png) | ![Android sign-in bottom sheet](images/android-cloud-signin.png) |

| iOS create account | iOS handover warning | iOS password reset |
| :---: | :---: | :---: |
| ![iOS create-account sheet with password confirmation](images/ios-cloud-signup.png) | ![iOS warning that the guest round will be set aside](images/ios-cloud-handover.png) | ![iOS password-reset sheet](images/ios-cloud-reset.png) |

| Android handover warning | Android password reset | iOS leaderboard |
| :---: | :---: | :---: |
| ![Android warning that the guest round will be set aside](images/android-cloud-handover.png) | ![Android password-reset bottom sheet](images/android-cloud-reset.png) | ![iOS leaderboard sheet](images/ios-cloud-leaderboard.png) |

QA-only output without promotion: `make screenshots-web-qa` writes `output/playwright/latest/`; `make screenshots-mobile-qa` writes `output/mobile/`.

---

## Feature matrix

| Capability | Web | iOS | Android |
| --- | :---: | :---: | :---: |
| Correct compaction, single-merge, and scoring rules | ✅ | ✅ | ✅ |
| No tile spawn after an ineffective move | ✅ | ✅ | ✅ |
| 90 % `2` / 10 % `4` weighted tile spawning | ✅ | ✅ | ✅ |
| One-step undo (board **and** score) | ✅ | ✅ | ✅ |
| Persistent best score across sessions | ✅ | ✅ | ✅ |
| Automatic session restore on launch | ✅ | ✅ | ✅ |
| Corrupt-save detection and safe discard | ✅ | ✅ | ✅ |
| Restart confirmation while a round is active | ✅ | ✅ | ✅ |
| Win state at 2048 with "keep playing" option | ✅ | ✅ | ✅ |
| Game-over detection on a full board with no merge | ✅ | ✅ | ✅ |
| In-app rules and strategy guide | ✅ | ✅ | ✅ |
| Server-driven content surfaces, with a native fallback | — | ✅ | ✅ |
| Swipe / drag gesture input | ✅ | ✅ | ✅ |
| Physical keyboard input (arrows + WASD) | ✅ | — | — |
| On-screen direction controls | ✅ | — | — |
| Fullscreen toggle | ✅ | — | — |
| Haptic feedback | — | ✅ | ✅ |
| Procedural sound cues with a mute toggle | ✅ | ✅ | ✅ |
| Separate guest and signed-in rounds on one device | ✅ | ✅ | ✅ |
| Reduced-motion support | ✅ | ✅ | ✅ |
| Screen-reader announcements | ✅ | ✅ | ✅ |
| Vector-only iconography | SVG | SF Symbols | Material vectors |
| Installable / distributable | PWA | `.app` | `.apk` |
| Works fully offline | ✅ | ✅ | ✅ |
| Optional account, cloud save sync, leaderboards | ✅ | ✅ | ✅ |
| Password confirmation, per-field reveal, and reset | ✅ | ✅ | ✅ |
| Mandatory network for a move | ❌ | ❌ | ❌ |

---

## How to play

Every move slides **all** tiles as far as they can go in one direction. When two tiles bearing the same number collide, they merge into a single tile of twice the value, and that new value is added to your score. After any move that actually changed the board, one new tile appears in a random empty cell — a `2` ninety percent of the time, a `4` the other ten.

The round ends when the board is full **and** no two adjacent tiles match, because at that point no move can change anything. Reaching a `2048` tile triggers the win state, but you are free to dismiss it and keep building toward 4096 and beyond.

Three practical habits carry most beginners a long way:

- **Anchor a corner.** Pick one corner, keep your largest tile there, and avoid any move that would dislodge it.
- **Keep one row or column as a "spine."** Build a descending run along the edge that holds your anchor so merges cascade naturally.
- **Treat the fourth direction as a last resort.** If you anchor bottom-left, moving up is what breaks the structure — spend it only when you have no alternative.

---

## Controls

| Action | Web | iOS | Android |
| --- | --- | --- | --- |
| Move | Arrow keys, `W`/`A`/`S`/`D`, swipe on the board, or the on-screen direction pad | Swipe the board in any direction | Swipe the board in any direction |
| Undo last move | Undo button | Undo button | Undo button |
| New game | New game button (confirms first if a round is in progress) | New game button (confirms first) | New game button (confirms first) |
| Sign in / account | Header account button | Account control | Account control |
| Leaderboard | Leaderboard button | Leaderboard | Leaderboard |
| Rules and help | About link | Help button | Help button |
| Fullscreen | `F` | — | — |
| Continue past 2048 | "Keep playing" in the win overlay | "Keep playing" | "Keep playing" |

A swipe registers once the gesture travels past a small threshold, so a single drag always produces exactly one move — never a burst.

---

## Behavioral invariants

These are the contract. Every client must satisfy all of them, and each one is covered by at least one automated test per platform.

1. A valid move compacts tiles toward the travel direction, merges each pair of equal neighbors **at most once per move**, adds the merged values to the score, and then spawns exactly one new tile.
2. An ineffective move — one where no tile can slide or merge — changes nothing: no score change, no new tile, and **no undo snapshot**.
3. Undo restores exactly the board and score as they were immediately before the most recent valid move. The snapshot is consumed on use, so undo is strictly one step.
4. Starting a new game preserves the best score and requires explicit confirmation whenever a round is already in progress.
5. Reaching 2048 presents a win state that the player may dismiss to continue playing. A full board with no available merge presents game over.
6. Persisted state is validated on load. Anything structurally invalid — wrong board length, non-power-of-two values, negative scores, malformed JSON — is discarded and replaced with a fresh game rather than crashing or restoring a corrupt board.
7. Randomness is injectable in every client so tests are fully deterministic, while production always uses unbiased platform randomness.
8. The guest round and the signed-in round are separate. Signing in warns before taking a round off the screen, parks it untouched, and loads the account's own; signing out restores it exactly, best score included. Career statistics come from the account and are never lifted from local storage.
9. A sound cue is heard now or dropped. No client queues a cue it cannot play immediately — a backlog arriving seconds after the moves that caused it is worse than silence.

---

## Architecture

Three clients, three runtimes, one contract. There is no shared rules library. Play is local-first: a move never requires the network. An optional Cloud API (`server/`) adds accounts, cross-device sync, and leaderboards — see [docs/backend.md](docs/backend.md).

| Concern | Web | iOS | Android |
| --- | --- | --- | --- |
| UI layer | `index.html`, `Web-Version/style.css` | `GameView.swift`, `ContentView.swift` | `MainActivity.kt` + Compose theme |
| Rules engine | `Web-Version/game-engine.js` (pure, side-effect free) | `GameViewModel.swift` | `GameViewModel.kt` |
| State orchestration | `Web-Version/script.js` | `GameViewModel.swift` | `GameViewModel.kt` |
| Persistence | `localStorage`, key `game2048-state-v2` | `UserDefaults` | `GameStorage.kt` over `SharedPreferences` |
| Server-driven content | — | `Game-2048/SDUI/` | `sdui/` package |
| Unit tests | Node.js built-in test runner | XCTest | JUnit 4 |
| UI / integration tests | Playwright (Chromium) | XCUITest | Compose UI Test + Espresso |
| Language | JavaScript (ES modules) | Swift 5 | Kotlin 1.9 |

**The move algorithm**, identical in all three: for each row or column taken in travel order, drop the empty cells, walk the remaining values merging adjacent equal pairs exactly once, pad the line back to length four with zeros, and write it back. Compare the resulting board to the original — spawn a tile only if they differ.

**The lifecycle**, identical in all three:

1. Load persisted state and validate it, or build a fresh board with two starting tiles.
2. Accept a direction from keyboard, button, or gesture input.
3. Resolve the move atomically, capturing an undo snapshot first if the move is valid.
4. Persist board, score, best score, and win-continuation flag.
5. Evaluate the win and game-over predicates and present the matching UI.

**Web delivery** is static files served from `/2048-Game/` on GitHub Pages. Canonical URLs, manifest scope, sitemap entries, and crawler discovery links must all keep that base path. The local development server deliberately disables caching so UI edits reload predictably.

Deeper detail lives in [`ARCHITECTURE.md`](ARCHITECTURE.md) for the whole system, and [`docs/architecture.md`](docs/architecture.md) for per-client specifics.

---

## Cloud API

Optional Express + MongoDB Atlas service for accounts, JWT auth, cross-device save sync, scores, and leaderboards. Live at [game-2048-cloud-api.vercel.app](https://game-2048-cloud-api.vercel.app) — the service root (`/`) redirects to Swagger UI at `/docs`.

| Surface | URL |
| --- | --- |
| Swagger UI | [/docs](https://game-2048-cloud-api.vercel.app/docs) |
| Redoc | [/redoc](https://game-2048-cloud-api.vercel.app/redoc) |
| Scalar | [/reference](https://game-2048-cloud-api.vercel.app/reference) |
| OpenAPI JSON | [/openapi.json](https://game-2048-cloud-api.vercel.app/openapi.json) |

Play stays local-first: declining an account leaves the board unchanged. Full contract, sync rules, and local run notes: [`docs/backend.md`](docs/backend.md). Privacy: [`docs/privacy.md`](docs/privacy.md).

---

## Server-driven surfaces

Both native clients ship a **server-driven UI runtime that does not fetch over the network today.**

Store review takes days. A typo in the help copy should not have to wait that long, and every mature store app solves this by describing the screen with data rather than code it ships. Help surfaces are described by JSON, validated, and rendered natively from the app bundle — the same contract that could later load from a publisher without rewriting the renderer. The optional Cloud API handles accounts and sync; it does not drive help copy today. Adding a remote surface source later is one new `SurfaceSource` and one line of wiring; the renderer, validator, and every test stay untouched.

**The game is never server-driven.** Board, merging, scoring, and undo are code, and no payload can reach them. What is describable is content — the help sheet today.

| A payload may | A payload may not |
| --- | --- |
| Supply text, ordering, and structure | Supply colours, fonts, or spacing |
| Name an action the host already implements | Describe behaviour, expressions, or scripts |
| Introduce a node type this build skips | Touch the rules engine or persisted state |
| Gate itself to a minimum app version | Force a screen to render nothing |

Actions are **names**. A surface can ask for `newGame`; it cannot describe how to start one. That indirection is what keeps a data channel from becoming an execution channel.

Every surface has a hand-written native fallback. Missing, unreadable, schema too new, app too old, or every node unknown all end at the shipped UI, and individual bad nodes are pruned while their siblings render. Delete every payload and both apps are exactly what they shipped with — the feature is additive, never load-bearing.

The iOS and Android payloads are byte-identical and a test asserts they stay that way, for the same reason the rules have three parallel suites: two clients drifting apart is the failure mode this repository exists to prevent.

Full detail in [`ARCHITECTURE.md`](ARCHITECTURE.md#server-driven-surfaces).

## Repository map

```text
.
├── index.html                          Web entry point, SEO metadata, JSON-LD
├── 404.html                            GitHub Pages fallback page
├── manifest.json                       PWA manifest (icons, shortcuts, scope)
├── robots.txt / sitemap.xml            Crawler directives and canonical URL set
├── llms.txt / llms-full.txt            Machine-readable product documentation
├── humans.txt                          Credits
├── Makefile                            Stable developer command surface
├── CITATION.cff                        Citation metadata
│
├── Web-Version/
│   ├── game-engine.js                  Pure deterministic rules engine
│   ├── script.js                       State, input handling, persistence, DOM
│   ├── cloud.js / account.js           Optional Cloud API client and account UI
│   ├── style.css                       Shared visual system and responsive layout
│   └── about.html                      Rules and strategy guide
│
├── Game-2048/                          SwiftUI client
│   ├── Game_2048App.swift              App entry point
│   ├── GameView.swift                  Responsive native board and controls
│   ├── GameViewModel.swift             Rules, scoring, undo, persistence
│   ├── Cloud/                          Optional account, sync, leaderboard
│   └── Assets.xcassets                 App icons and colors
├── Game-2048Tests/                     XCTest model and cloud tests
├── Game-2048UITests/                   XCUITest interaction and launch tests
├── 2048 Game.xcodeproj                 Xcode project (scheme: Game-2048)
│
├── Android-Version/Game2048/           Jetpack Compose client
│   ├── app/src/main/java/…             MainActivity, GameViewModel, cloud/, GameStorage, theme
│   ├── app/src/test/java/…             JUnit ViewModel and cloud tests
│   ├── app/src/androidTest/java/…      Compose instrumentation tests
│   └── gradle/libs.versions.toml       Version catalog
│
├── server/                             Optional Cloud API (Express + MongoDB Atlas)
│
├── tests/
│   ├── web/                            Engine, static-metadata, and browser tests
│   └── tooling/                        Repository-structure tests
├── scripts/                            Bootstrap, doctor, checks, per-platform test runners
├── docs/                               Architecture, testing, and agent-harness guides
├── images/                             App icons, brand mark, share art, screenshots
│
├── .github/
│   ├── workflows/                      CI, dependency review, labeler
│   ├── ISSUE_TEMPLATE/                 Bug and feature forms
│   └── CONTRIBUTING.md · SECURITY.md · SUPPORT.md · CODE_OF_CONDUCT.md
├── .agents/skills/                     Canonical coding-agent workflows
├── .claude/skills/                     Claude Code adapters
└── .devcontainer/                      Node 22, JDK 17, Android SDK 34 container
```

`output/` is generated locally by the QA and screenshot scripts and is intentionally not versioned — it is fully reproducible with `make test`, `make screenshots-web`, and `make screenshots-mobile` on a host with both native runtimes.

---

## Getting started

| Target | Requirements | Supported hosts |
| --- | --- | --- |
| Web | Node.js 22+, npm | macOS, Linux, Windows, dev container |
| Web browser tests | The above, plus Chromium via `npx playwright install chromium` | macOS, Linux, dev container |
| iOS | Xcode 15.3+, iOS 17.4+ simulator or device | macOS only |
| Android | Android SDK 34, API 24+ emulator or device. **No JDK setup needed** — Gradle downloads its own JDK 17. | macOS, Linux, Windows, dev container |

**You do not need to configure a JDK for Android.** Gradle 8.13 daemon JVM criteria are committed in `Android-Version/Game2048/gradle/gradle-daemon-jvm.properties`, so the first `./gradlew` invocation downloads a matching Adoptium JDK 17 for your OS and architecture and runs on it — even if your machine's default `java` is a different version, and even if you have no JDK at all. This is the single most common Android onboarding failure, and it is designed out rather than documented around.

Clone and bootstrap:

```bash
git clone https://github.com/hoangsonww/2048-Game.git
cd 2048-Game
make setup     # installs locked npm dependencies and activates Git hooks
make doctor    # reports which platform toolchains this machine can build
make help      # lists every supported workflow
```

`make doctor` is the fastest way to find out what you can run locally. It reports the status of Git, Node, npm, the JDK, ShellCheck, Docker, `xcodebuild`, `xcrun`, `ANDROID_HOME`, and `adb`, so you know up front whether the iOS or Android suites are available before you try them.

To include the Chromium download that the browser tests need, run setup as:

```bash
./scripts/bootstrap.sh --with-browser
```

Plain `make setup` skips it to keep first-run setup light, and prints the one-line command to add it later.

Then run any client with a single command:

```bash
make serve         # web app at http://localhost:8080
make android-run   # build, install, and launch on a device or emulator
make ios-run       # build, install, and launch on a simulator
```

**Dev container.** `.devcontainer/` provisions Node.js 22, JDK 17, Android SDK 34 with build-tools 34.0.0, ShellCheck, GNU Make, the GitHub CLI, and Chromium for Playwright, on top of the Microsoft Java 17 Bookworm base image. Open the repository in VS Code and choose **Reopen in Container**, or use GitHub Codespaces.

It covers the complete web and Android JVM workflows out of the box. **iOS cannot be containerized** — Xcode is macOS-only and its license forbids redistribution, so iOS builds always require a macOS host. That is a platform constraint, not a gap in this setup.

To verify the container yourself:

```bash
make verify-devcontainer               # build the image and check every tool
./scripts/verify-devcontainer.sh --build   # additionally build the Android client inside it
```

The `--build` form uses an isolated `git archive` copy rather than mounting your working tree, so a container build never contends with a host build over the same Gradle output directory.

**Git hooks.** Husky activates during `npm install`: `pre-commit` runs the fast repository checks and `pre-push` runs the full web suite. Contributors who prefer the Python framework can install the equivalent hooks from `.pre-commit-config.yaml` with `pre-commit install --install-hooks`.

---

## Run the web app

```bash
npm install
npm start          # or: make serve
```

Open `http://localhost:8080`. The app is entirely static — no bundler, no transpiler, no production build step, and no third-party runtime dependencies. The only external resource it touches is the Google Fonts stylesheet for the display typeface, and the layout degrades gracefully to system fonts if that request is blocked.

Run the full web suite:

```bash
npx playwright install chromium    # one-time browser download
npm test                           # or: make test-web
```

Capture deterministic UI screenshots across desktop and mobile viewports:

```bash
make screenshots-web
```

Output lands in `output/playwright/` (gitignored) covering gameplay, the restart dialog, win, loss, and the About page at both breakpoints.

With an iPhone simulator and Android emulator already booted, refresh the native canonical set with `make screenshots-mobile`. The script installs the current Android APK, captures both clients through accessibility-labelled controls, and exports the iOS frames from XCTest attachments.

---

## Run the iOS app

Requirements: Xcode 15.3 or newer, targeting iOS 17.4+. The app builds for both iPhone and iPad.

The fastest path needs no Xcode UI and no device UDID — one command builds, installs, and launches on an automatically selected simulator:

```bash
make ios-run
```

Other entry points:

```bash
make ios-devices   # list available iPhone simulators
make ios-boot      # boot a simulator and open Simulator.app
make ios-build     # build only
make test-ios      # full model + UI test run with coverage
```

Every one of these resolves a simulator for you. To pin a specific device, set `IOS_SIMULATOR_ID` to a UDID from `make ios-devices`.

To work in Xcode instead:

1. Open `2048 Game.xcodeproj`.
2. Select the **Game-2048** scheme and any iPhone or iPad simulator.
3. Run with `⌘R`. Run the unit and UI tests with `⌘U`.

---

## Run the Android app

Requirements: Android SDK 34 and an API 24 or newer emulator or device. `minSdk` is 24; `compileSdk` and `targetSdk` are 34. **A JDK is not a prerequisite** — Gradle provisions its own.

Build, install, and launch on a connected device or emulator in one command:

```bash
make android-run
```

Other entry points, all from the repository root:

```bash
make android-build          # debug APK
make android-install        # build and install
make android-tasks          # list every available Gradle task
make android-clean          # remove build output
make test-android           # unit tests, lint, and APK assembly
make test-android-device    # adds the Compose suite on a connected device
make gradle ARGS="assembleRelease"   # any other Gradle task
```

Every one of these routes through `scripts/android.sh`, which guarantees a correct JDK before invoking Gradle.

Raw Gradle also works, thanks to the committed daemon JVM criteria:

```bash
cd Android-Version/Game2048
./gradlew assembleDebug
```

The first run downloads a matching JDK 17 (roughly 180 MB, cached in `~/.gradle/jdks/`) and every run after that is fast.

To work in Android Studio instead, open `Android-Version/Game2048`, let the Gradle sync finish, then run the `app` configuration.

The debug APK is written to `Android-Version/Game2048/app/build/outputs/apk/debug/app-debug.apk`. If you only want to *play* the Android app, download the prebuilt APK from the [latest release](https://github.com/hoangsonww/2048-Game/releases/latest) instead — no toolchain required.

---

## Command reference

Every workflow has a stable `make` entry point. Prefer these over ad-hoc commands — they are what CI and the Git hooks call.

| Command | What it does | Requires |
| --- | --- | --- |
| `make help` | Lists all supported workflows | — |
| `make setup` | Installs locked dependencies and activates Git hooks | Node 22+ |
| `make doctor` | Reports which platform toolchains are available | — |
| `make serve` | Serves the web app at `http://localhost:8080` | Node 22+ |
| `make check` | Fast syntax, repository, shell, SEO, and discovery checks | Node 22+ |
| `make version` | Prints the version and checks every client agrees | — |
| `make version-sync` | Rewrites the derived version fields from `VERSION` | — |
| `make test-web` | Complete deterministic and browser web suite | Node 22+, Chromium |
| `make android-build` | Builds the Android debug APK | SDK 34 |
| `make android-install` | Builds and installs on a connected device | SDK 34 + device |
| `make android-run` | Installs and launches on a connected device | SDK 34 + device |
| `make android-tasks` | Lists every available Gradle task | SDK 34 |
| `make android-clean` | Removes Android build output | SDK 34 |
| `make gradle ARGS="…"` | Runs any Gradle task with a correct JDK | SDK 34 |
| `make test-android` | Android unit tests, lint, and debug APK | SDK 34 |
| `make test-android-device` | Adds Compose tests on a connected device | Above + emulator/device |
| `make ios-build` | Builds the iOS app for a simulator | macOS, Xcode |
| `make ios-run` | Builds, installs, and launches on a simulator | macOS, Xcode |
| `make ios-boot` | Boots a simulator and opens Simulator.app | macOS, Xcode |
| `make ios-devices` | Lists available iPhone simulators | macOS, Xcode |
| `make test-ios` | iOS unit and UI tests on an available simulator | macOS, Xcode |
| `make test` | Every suite this host can support | Varies |
| `make screenshots-web` | Deterministic desktop/mobile + cloud UI captures; promotes into `images/` | Node 22+, Chromium |
| `make screenshots-web-qa` | Same captures into `output/` only (no promote) | Node 22+, Chromium |
| `make screenshots-mobile` | iOS/Android game + cloud UI captures; promotes into `images/` | macOS, Xcode, SDK 34, booted simulator + emulator |
| `make screenshots-mobile-qa` | Same native captures into `output/mobile/` only | Same as above |
| `make clean-web` | Removes generated coverage and local screenshots | — |

---

## Testing and quality gates

Coverage is layered deliberately: pure rules logic is tested exhaustively and cheaply, while the expensive browser, simulator, and emulator suites focus on real user flows that unit tests cannot reach.

### Web — 253 tests, 100 % line coverage

- **23 deterministic engine tests** against `game-engine.js`, covering all four directions, merge ordering and the single-merge rule, scoring, weighted spawning at its exact boundary, ineffective moves, undo semantics, win and loss predicates, and rejection of structurally invalid boards.
- **45 controller tests** against `script.js`, run on a hand-written DOM so keyboard, touch, on-screen buttons, rendering, message states, and persistence are all covered without a browser. Includes the gesture-ownership contract: the `touchmove` listener must be non-passive, must suppress scrolling only during a board swipe, and must forget a cancelled gesture.
- **34 cloud-bridge tests** for the guest and account storage profiles: that signing in parks the guest round rather than uploading it, that signed-in play never writes to the guest slot, and that signing out restores the guest round exactly.
- **47 cloud-client tests** for auth, token refresh, sync resolutions, password reset, and the rule that career statistics are never lifted from local storage, plus **72 account-surface tests** for the dialogs, the handover warning, password confirmation, and the reveal controls.
- **13 sound tests** proving a cue is dropped rather than queued whenever it cannot be played now.
- **5 metadata and asset tests** for the manifest, sitemap, `robots.txt`, JSON-LD, form patterns, and every referenced icon, plus **2 repository-tooling tests** asserting the project structure and npm script surface stay intact.
- **13 Chromium interaction scenarios** driving the real page: arrow-key play, WASD play, touch swipe, the on-screen direction pad, undo, persistence across reload, restart confirmation, fullscreen, the win overlay, the loss overlay, recovery from a corrupt saved state, board-swipe ownership, real-clock sound timing, account and password flows, and responsive layout from a 320 px phone through tablet widths.

Coverage is **enforced** by `c8` across everything in `Web-Version/`, and the build fails below 100 % statements, 100 % lines, 100 % functions, or 95 % branches. It currently reaches **100 % statements, lines, and functions with 95.1 % branches**.

### iOS — 183 tests, 95.1 % domain line coverage

- **80 deterministic model, surface, and render tests** covering every direction, merge ordering, scoring, spawn distribution and index clamping, restart, undo depth and win-state rewind, persistence round-trips, best-score retention, win and loss detection, and rejection of every shape of invalid saved state.
- **16 profile and sound tests** covering guest / account separation, the career-best seed, and the cue renderer's envelope and pitch slide.
- **74 cloud tests** across the API client, the controller state machine, the token store, and the wire models — including password reset, every unexpected-failure path, and the rule that career statistics come from the account alone.
- **12 XCUITest simulator tests** covering the help sheet, swipe gestures, the restart confirmation dialog, accessibility identifiers and labels, end-state recovery flows, launch performance, the account and reset sheets, the password confirmation and reveal controls, the sign-in handover warning, and that a vertical board swipe reaches the board without moving the screen. The suite reports thirteen executions because the launch test runs once per appearance mode.

Coverage is **enforced**: `scripts/test-ios.sh` reads the `.xcresult` with `xccov` and fails below 90 % line coverage of stable app/domain code, currently **95.1 %**. `GameView.swift` and `CloudViews.swift` are exercised by the simulator suite instead: Xcode versions expose different generated executable-line counts for SwiftUI view builders, so including them would make the same source pass or fail according to the installed compiler.

### Android — 213 tests, 97.2 % domain line coverage

- **49 deterministic ViewModel tests** proving the same rules and persistence contract as the other two clients, including the guest / account profile separation and the career-best seed.
- **33 server-driven surface tests** covering decoding, version gating, node pruning, source fallback, and the rule that every failure mode ends at the app's own native UI.
- **11 storage tests** covering `SharedPreferencesGameStorage` serialisation against an in-memory `SharedPreferences`, including truncated, non-numeric, and empty saved grids, and that the guest and account slots cannot see each other.
- **80 cloud tests** across the API client, the controller state machine, and the token store — including password reset and the rule that career statistics come from the account alone.
- **6 sound tests** proving a flood of cues is capped rather than buffered, and that an unavailable audio device costs the game nothing.
- **20 Compose instrumentation tests** on an API 34 emulator covering the help sheet, swipe and undo, restart confirmation, win/loss recovery, the guest invite, the account surface, the sign-in destination, the sign-in handover warning, and the password confirmation, reveal, and reset flows.

Coverage is **enforced** by JaCoCo: `make test-android` fails below 90 % line or 85 % branch coverage of the Kotlin rules engine and storage, currently **97.2 % lines and 85.7 % branches**. `MainActivity` and `CloudUi` are Compose and are measured by the device suite instead.

### Static and repository checks

`make check` runs on every commit through Husky and validates JavaScript syntax, JSON well-formedness, repository structure, required SEO and discovery files, `llms.txt` availability, staged-file whitespace, and — when ShellCheck is installed — every shell script in `scripts/` and `.husky/`.

```bash
make check        # fast pre-commit checks
make test-web     # full web suite
make test-ios     # macOS + Xcode
make test-android # JDK 17 + SDK 34
make test         # everything this host supports
```

More detail, including how to diagnose flaky device runs, is in [`docs/testing.md`](docs/testing.md).

---

## Continuous integration

[Cross-platform CI](.github/workflows/ci.yml) runs on every push to `main`, every pull request, and on manual dispatch. It is split into six independently visible jobs so a failure points straight at the responsible platform:

| Job | Runner | Covers |
| --- | --- | --- |
| **Web** | `ubuntu-latest` | `npm audit`, syntax, repository and SEO validation, ShellCheck, enforced engine coverage, Chromium flows |
| **iOS** | `macos-15` | `build-for-testing`, XCTest model coverage, XCUITest interaction and accessibility flows |
| **Android JVM** | `ubuntu-latest` | ViewModel unit tests, Android lint, debug APK assembly |
| **Android device** | `ubuntu-latest` + KVM | API 34 `pixel_6` emulator running the full Compose instrumentation suite |
| **Docker** | `ubuntu-latest` | `linux/amd64` and `linux/arm64` image build, a smoke test that actually serves the game, and publication to GHCR |
| **Android builder** | `ubuntu-latest` | `linux/amd64` SDK image, a containerized APK build with unit tests, and publication to GHCR |

Web coverage reports, Xcode `.xcresult` bundles, Android lint and test reports, and the debug APK are uploaded as workflow artifacts — including on failure, which is usually when you need them most.

### Container image

The web client is published to the GitHub Container Registry on every push to `main`:

```bash
docker run --rm -p 8080:8080 ghcr.io/hoangsonww/2048-game:latest
```

The image is the Node runtime, the static files, and the same `scripts/serve-web.mjs` that `make serve` runs — no bundler, no framework, and nothing installed from npm, because the game has no runtime dependencies. It runs as an unprivileged user and carries a health check.

**A pull request builds the image but never publishes it.** A fork's token cannot write packages, and pushing an image built from unreviewed code to a tag other people pull is not something a green check should do — so the publish step is reachable only from a commit that has already landed on a branch. Every pull request still proves the image builds on both architectures and that the running container serves the game, path traversal included.

### Building Android without Android Studio

The second image is a pinned JDK 17 and Android SDK 34 toolbox. Mount a checkout and build against it:

```bash
docker run --rm -v "$PWD:/src" -w /src/Android-Version/Game2048 \
    ghcr.io/hoangsonww/2048-game-android:latest ./gradlew assembleDebug
```

Or build an APK in one shot, without starting a container:

```bash
docker buildx build -f Dockerfile.android --target apk --output out .
```

CI does both: it verifies the toolchain inside the image, then builds the debug APK *from* that image and runs the unit tests, so the published toolbox is proven to still build the project rather than merely to contain the binaries. The resulting APK is uploaded as a workflow artifact. `linux/amd64` only — Google ships the Android command-line tools as x86_64 Linux binaries, so an arm64 image would build cleanly and then fail at `aapt2` and `d8`.

**iOS cannot be containerized, and this is not a gap that can be closed.** Docker containers are Linux; Xcode is macOS-only and has no Linux build; and Apple's licence forbids redistributing Xcode. Any one of those three is fatal on its own. iOS builds always require a macOS host.

Supporting automation: **dependency review** blocks pull requests that introduce known-vulnerable dependencies, and the **labeler** applies path-based platform labels automatically. Dependency updates are applied by hand — there is no bot opening upgrade pull requests. Issue forms, ownership rules, release-note categories, contribution guidance, support routing, and the security policy all live under `.github/`.

---

## Releases and downloads

Every tagged release carries a build of all three clients, so none of them
requires a toolchain to try:

| File | What it is |
| --- | --- |
| `2048-vX.Y.Z-debug.apk` | Android app — install directly on a device |
| `2048-vX.Y.Z-ios-unsigned.zip` | Unsigned iOS `.app` for a simulator, or to sign yourself |
| `2048-vX.Y.Z-web.zip` | The shipping web client — unzip and serve the folder |
| `SHA256SUMS-ios.txt`, `SHA256SUMS-web.txt` | Checksums for the two zips |

The latest is at [**Releases**](https://github.com/hoangsonww/2048-Game/releases/latest).
The web client also runs at [hoangsonww.github.io/2048-Game](https://hoangsonww.github.io/2048-Game/)
with no download at all.

The iOS artifact is unsigned on purpose. Signing needs a provisioning profile
and a team identifier, neither of which belongs in a public repository, so App
Store distribution stays outside this pipeline.

### One version, three clients

`VERSION` at the repository root is the only place the version is edited.
`scripts/version.sh` propagates it to `package.json`, `versionName` and
`versionCode` in the Gradle build, and `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` in every Xcode build configuration. `versionCode` is
derived — `MAJOR * 10000 + MINOR * 100 + PATCH`, so 2.1.3 is 20103 — rather
than tracked as a second number to forget.

The agreement is enforced, not assumed: `make check` and CI both fail on drift,
and the release pipeline checks again at the tag before building anything.
These five fields had drifted four ways at once, which is why the gate exists.

### Cutting one

Actions → **Cut release** → Run workflow, and pick `patch`, `minor`, or
`major`. It verifies the tree, bumps and propagates the version, opens a
changelog section, commits, tags, dispatches the builds at that tag, and then
confirms a release exists with its artifacts attached before reporting success.
`dry_run` shows what would happen without pushing anything.

Releasing by hand is no longer a supported path. [`docs/releasing.md`](docs/releasing.md)
covers the pipeline, the three non-obvious constraints it works around, and what
to do when a stage fails.

---

## Accessibility

Accessibility is treated as a behavioral requirement, not a finishing touch, and parts of it are covered by automated tests.

- **Keyboard.** The entire web game is playable without a pointer. Arrow keys and WASD move, `F` toggles fullscreen, and every control is reachable by `Tab` with a visible focus indicator.
- **Screen readers.** Moves, merges, score changes, and end states are announced through a live region on web, through accessibility labels and identifiers on iOS, and through Compose semantics on Android. The board itself is exposed as an explicit accessibility container.
- **Motion.** Tile animations respect the platform reduced-motion preference and degrade to instant state changes.
- **Contrast and targets.** Tile and text colors are chosen for readable contrast at every tile value, and interactive targets meet platform minimum sizes.
- **Iconography.** Every control uses real vector artwork — SVG on web, SF Symbols on iOS, Material vectors on Android — centered by geometry rather than by font metrics. ASCII, emoji, and Unicode glyphs are never used as icons, so nothing depends on a font that may not load.
- **Layout.** Compact and large breakpoints are both verified, including safe-area insets on iOS and gesture-navigation insets on Android.

---

## Privacy and data handling

**Local-first by default.** Without an account, nothing leaves your device.

- No analytics SDK, advertising SDK, or crash reporter.
- Game state lives in `localStorage` on web, `UserDefaults` on iOS, and `SharedPreferences` on Android — removable by clearing site data or deleting the app.
- The only non-game outbound request the web client may make is Google Fonts for the display typeface; the app remains fully playable if that request is blocked.

**Optional account.** Creating an account enables cross-device save sync, scores, and leaderboards against the Cloud API. Declining the invitation leaves play unchanged. Details: [docs/privacy.md](docs/privacy.md) and [docs/backend.md](docs/backend.md).

---

## Web discoverability and PWA install

The web client ships production-grade metadata: canonical and `hreflang` links, Open Graph and Twitter card tags with dedicated share artwork, `schema.org` `WebSite` and `VideoGame` JSON-LD structured data, a complete `sitemap.xml`, `robots.txt` advertising that sitemap, and both `llms.txt` and `llms-full.txt` describing the product in a machine-readable form for language models.

The PWA manifest supplies maskable 192 px and 512 px icons, an SVG favicon with an `.ico` fallback, app shortcuts for "new round" and "how to play", standalone display with `window-controls-overlay` override, and a themed splash color. On Chrome or Edge, use **Install app** in the address bar; on iOS Safari, use **Share → Add to Home Screen**. Once installed the game runs full screen and works entirely offline.

---

## Agent-ready development

[`AGENTS.md`](AGENTS.md) is the shared source of truth for architecture, behavioral invariants, commands, and change discipline. Repository-local skills in `.agents/skills/` provide focused workflows for web, iOS, Android, cross-platform parity, and release readiness, and thin adapters keep Claude Code, GitHub Copilot, Cursor, Gemini CLI, Windsurf, and Codex-compatible harnesses aligned on the same instructions rather than drifting apart.

Skills are task routers, not blanket permission — an agent must still respect the requested scope and preserve unrelated working-tree changes. See [`docs/agent-harness.md`](docs/agent-harness.md) for the recommended sequence.

---

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `npm test` fails on the browser step | Chromium is not installed. Run `npx playwright install chromium`. |
| `make test-ios` reports no simulator | No available iPhone runtime. Check `xcrun simctl list devices available`, then pin one with `IOS_SIMULATOR_ID=<udid>`. |
| Gradle cannot find the Android SDK | `ANDROID_HOME` is unset, or `local.properties` is missing. `local.properties` is machine-local and intentionally not committed — Android Studio regenerates it on first sync. |
| `Android Gradle plugin requires Java 17` on a raw `./gradlew` | Your default JDK is older and the daemon JVM criteria were not picked up. Use `make android-build`, which resolves a JDK 17 explicitly, and confirm `Android-Version/Game2048/gradle/gradle-daemon-jvm.properties` is present. |
| First Android build is slow | Gradle is downloading its own JDK 17 (~180 MB) and the Gradle distribution. Both are cached; later builds take seconds. |
| `adb: command not found` | `platform-tools` is not on `PATH`. The `make` targets resolve `adb` from `ANDROID_HOME` automatically — use `make android-run` rather than calling `adb` directly. |
| `connectedDebugAndroidTest` hangs or loses the hierarchy | An emulator/ADB harness failure rather than an app defect. Check `adb logcat`, restart the emulator without wiping data, and rerun the exact failing test before filing a bug. |
| Port 8080 already in use | Another server is bound. Stop it, or run the static server on a different port. |
| The web page looks stale after an edit | The dev server disables caching, but a service-worker-style hard cache in the browser can persist. Hard-reload with `⌘⇧R` / `Ctrl+Shift+R`. |
| ShellCheck steps are skipped locally | ShellCheck is optional locally but required in CI. Install it (`brew install shellcheck`) to catch shell issues before pushing. |

---

## Contributing

Small, focused pull requests are very welcome. Before opening one:

1. Read [`.github/CONTRIBUTING.md`](.github/CONTRIBUTING.md) and [`AGENTS.md`](AGENTS.md).
2. Keep the game rules consistent across all three clients, or explicitly document an intentional platform difference.
3. Use platform-native vector icons — never text glyphs.
4. Add a test for behavior changes, or include a clear manual verification note describing exactly what you checked.
5. Run `make check` plus the full suite for every platform you touched, and attach screenshots for UI changes.

Issue forms for [bug reports](https://github.com/hoangsonww/2048-Game/issues/new?template=bug_report.yml) and [feature requests](https://github.com/hoangsonww/2048-Game/issues/new?template=feature_request.yml) are available. Participation is governed by the [Code of Conduct](.github/CODE_OF_CONDUCT.md), and [`.github/SUPPORT.md`](.github/SUPPORT.md) explains where to ask questions.

---

## Security

The clients are local-first and play without an account. The optional Cloud API adds auth and sync — see [`.github/SECURITY.md`](.github/SECURITY.md) for the disclosure process. Do not open a public issue for a suspected vulnerability.

---

## Citation

If this project is useful in academic work or you want to reference its cross-platform parity approach, citation metadata is provided in [`CITATION.cff`](CITATION.cff). GitHub renders a ready-to-copy APA and BibTeX citation from that file via the **Cite this repository** button on the repository sidebar.

---

## License and credits

Released under the [MIT License](LICENSE).

Created and maintained by [Son Nguyen](https://github.com/hoangsonww). The original 2048 concept is by Gabriele Cirulli; this is an independent implementation and is not affiliated with or endorsed by the original author.
