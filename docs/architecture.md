# Architecture

This document is the authoritative description of how the three clients are built and what they must have in common. Read it before changing game rules, state handling, or persistence in any client.

## Table of contents

- [Design principle](#design-principle)
- [Runtime boundaries](#runtime-boundaries)
- [The rules model](#the-rules-model)
- [The move algorithm](#the-move-algorithm)
- [Scoring](#scoring)
- [Tile spawning and injectable randomness](#tile-spawning-and-injectable-randomness)
- [Undo](#undo)
- [Terminal states](#terminal-states)
- [Persistence and state validation](#persistence-and-state-validation)
- [Application lifecycle](#application-lifecycle)
- [Web client](#web-client)
- [iOS client](#ios-client)
- [Android client](#android-client)
- [Web delivery and base paths](#web-delivery-and-base-paths)
- [Making a parity-safe change](#making-a-parity-safe-change)

## Design principle

The repository contains three offline-first clients. There is **no shared backend, no shared runtime library, and no generated cross-platform layer**. Each client is written idiomatically for its platform.

That is a deliberate trade. A shared core would guarantee parity mechanically but would force a lowest-common-denominator architecture onto all three platforms and add a build step to a project that otherwise needs none. Instead, parity is maintained by three explicit mechanisms:

1. **This document plus [`AGENTS.md`](../AGENTS.md)** define the contract in prose precise enough to implement against.
2. **Each client independently proves the contract** with its own deterministic rules tests.
3. **CI runs all three toolchains on every pull request**, so a parity regression anywhere fails the build.

The cost of this approach is that a rules change must be made three times. That is accepted, and it is why the invariant list below is written to be unambiguous.

## Runtime boundaries

| Concern | Web | iOS | Android |
| --- | --- | --- | --- |
| UI | `index.html`, `Web-Version/style.css` | `GameView.swift`, `ContentView.swift` | `MainActivity.kt`, Compose theme files |
| Rules engine | `Web-Version/game-engine.js` | `GameViewModel.swift` | `GameViewModel.kt` |
| State orchestration | `Web-Version/script.js` | `GameViewModel.swift` | `GameViewModel.kt` |
| Persistence | `localStorage`, key `game2048-state-v2` | `UserDefaults` | `GameStorage.kt` over `SharedPreferences` |
| Unit tests | Node.js test runner | XCTest | JUnit 4 |
| UI tests | Playwright (Chromium) | XCUITest | Compose UI Test |
| Language | JavaScript (ES modules) | Swift 5 | Kotlin 1.9 |

Only the web client separates the pure engine from the orchestration layer into distinct files. `game-engine.js` is side-effect free and importable from both the browser and Node, which is what allows its coverage to be enforced cheaply. On iOS and Android the equivalent logic lives inside the view model but must remain free of view dependencies so it stays unit-testable without a simulator or emulator.

## The rules model

Every board is a 4×4 collection whose cells contain either zero (empty) or a positive power of two. Boards are addressed with the origin at the top-left; rows increase downward and columns increase rightward. The web client exposes this exact coordinate system through its `render_game_to_text()` debug hook, and tests depend on it.

## The move algorithm

A move processes each row or column **in travel order** — the line nearest the destination edge is resolved first — and applies four steps:

1. Remove empty cells, preserving order.
2. Walk the remaining values left to right, merging each adjacent equal pair into a single doubled tile. **A tile that was produced by a merge cannot merge again in the same move.** This is why `[2, 2, 4]` moving left becomes `[4, 4]` and not `[8]`.
3. Pad the line back to length four with zeros on the trailing side.
4. Write the line back to the board.

After all lines are processed, compare the resulting board with the pre-move board. If they are identical the move was **ineffective**: no tile spawns, the score does not change, and no undo snapshot is created. If they differ the move was **valid** and exactly one new tile spawns.

The comparison against the pre-move board is the single source of truth for move validity. Do not track validity by counting merges or slides separately — that has historically been the source of parity bugs, particularly around moves that slide tiles without merging any.

## Scoring

The score increases by the value of each **newly created** merged tile. Merging two `4` tiles adds `8`. A move producing two separate merges adds the sum of both results. Sliding without merging adds nothing.

`best` is the maximum score ever achieved and **never decreases** — not on a new game, not on undo, and not when a saved game is discarded as corrupt.

## Tile spawning and injectable randomness

After a valid move, one tile spawns in a uniformly random empty cell. Its value is `2` with 90 % probability and `4` with 10 % probability.

Every client must allow this randomness to be injected so tests are deterministic:

- Web: the engine accepts a random provider function.
- iOS: the view model accepts an injected generator; UI tests additionally use launch arguments.
- Android: the view model accepts an injected generator; instrumentation tests use launch state.

Production code paths must always use unbiased platform randomness. Never ship a seeded or predictable generator as the default.

## Undo

Undo is strictly **one step**. Before a valid move is applied, the client captures a snapshot containing the exact pre-move board and score. Undo restores that snapshot and then **consumes** it, so undo cannot be pressed twice in a row to walk further back.

An ineffective move must not create a snapshot. Failing to honor that produces the most commonly reported parity bug in this codebase: pressing a direction against a wall, then pressing undo, and watching the board jump back an extra move.

## Terminal states

**Win.** Presented the first time any tile reaches 2048. The player may dismiss the overlay and continue playing; a persisted continuation flag prevents the win state from being presented again in the same round.

**Game over.** Presented when the board is full **and** no two orthogonally adjacent tiles are equal, since at that point no direction can change the board. Checking fullness alone is insufficient — a full board with an available merge is still playable.

## Persistence and state validation

Each client persists the board, score, best score, and win-continuation flag after every state change, and restores them at launch.

Restored state is **always validated before use**. A saved payload is rejected if it is malformed JSON, has the wrong board length, contains values that are not zero or a positive power of two, contains a negative score, or is missing required fields. Rejected state is discarded and replaced with a fresh game. The best score is preserved across a discard where it is independently readable.

This matters because saved state is user-writable on every platform — browser dev tools, a jailbroken device, a rooted emulator. A corrupt save must never crash the app or restore an impossible board.

## Application lifecycle

1. Restore and validate persisted state, or create a fresh board seeded with two tiles.
2. Accept a direction from keyboard, on-screen control, or gesture input.
3. Resolve exactly one move atomically, capturing an undo snapshot first when the move is valid.
4. Persist board, score, best score, and continuation flag.
5. Evaluate the win and game-over predicates and present the matching UI.

Input handling must guarantee **one move per discrete input**. A single continuous drag produces exactly one move, not a stream of them — enforced with a gesture threshold plus a per-gesture latch on all three clients.

## Web client

Static files with no bundler, transpiler, or runtime dependencies. `game-engine.js` is pure and dual-target (browser and Node), which keeps enforced coverage cheap and fast. `script.js` owns DOM wiring, input handling, persistence, and the accessibility live region.

Input sources: arrow keys, WASD, `touchstart`/`touchend` swipe on `#gridContainer` with a 28 px threshold, and on-screen direction buttons. `F` toggles fullscreen.

The board sets `touch-action: none`, `html`/`body` set `overscroll-behavior: none`, and a non-passive `touchmove` listener scoped to the board calls `preventDefault()`. The existing touch listeners are passive and cannot, so without that guard a board swipe chains into pull-to-refresh and rubber-band scrolling. A `touchcancel` handler clears the start point; otherwise a cancelled gesture leaves the board suppressing scrolling and measures the next swipe from a stale origin.

The client exposes `window.render_game_to_text()`, a JSON debug snapshot of the coordinate system, board, score, best, undo availability, and available moves. Browser tests and manual verification both rely on it; keep it accurate when state shape changes.

The local development server intentionally disables caching so UI work reloads predictably.

## iOS client

SwiftUI, targeting iOS 17.4+ for both iPhone and iPad. Uses `UserDefaults` for persistence, `UINotificationFeedbackGenerator`-class haptics, SF Symbols for all control iconography, and accessibility identifiers on every interactive element so XCUITest can drive real flows.

The board is exposed as an explicit accessibility container rather than a pile of individually focusable cells, which is what makes VoiceOver navigation coherent.

Layout is size-responsive rather than fixed — do not reintroduce hard-coded board dimensions.

**The board must never sit inside a scrolling container.** A `ScrollView`'s pan is a UIKit gesture recogniser, so it outranks the board's SwiftUI `DragGesture` outright: every vertical swipe reaches the scroll view and no tile ever moves. Neither `.highPriorityGesture` nor `.scrollBounceBehavior` changes that. The layout is therefore sized to fit the viewport, with `ViewThatFits(in: .vertical)` falling back to a scrolling layout only where the content genuinely cannot fit — very small devices, or the largest accessibility text sizes — where reaching the controls matters more than swipe fidelity. If you add vertical content here, keep the static branch fitting, and check `app.scrollViews` is empty in the UI tests.

## Android client

Jetpack Compose with Material 3, `minSdk` 24 and `compileSdk`/`targetSdk` 34, Kotlin 1.9 with AGP 8.3.1 on Gradle 8.13. State lives in a `ViewModel`; persistence goes through `GameStorage.kt` over `SharedPreferences`.

No JDK needs to be installed. `gradle/gradle-daemon-jvm.properties` pins daemon JVM criteria, so Gradle downloads and runs on its own Adoptium JDK 17 matching the host OS and architecture; `scripts/android.sh` additionally prefers a local JDK 17 when one exists.

Grid updates are **immutable** — produce a new board rather than mutating in place. In-place mutation previously broke Compose recomposition and reverse-direction merges simultaneously, and it is the single most important Android-specific constraint in this codebase.

Iconography uses Material vector assets, including the adaptive launcher icon. Compose semantics back the instrumentation tests.

The board's `detectDragGestures` **must consume each `PointerInputChange`**. The root column scrolls vertically, so an unconsumed change is delivered to the parent scroll as well and a board swipe drags the whole screen.

Tile animation mirrors the other clients rather than inventing its own timing: the background colour eases over 180 ms (web's `.cell` transition), a tile that gains a value springs from 82 % to full size (web's `pop` keyframe), values cross-fade through `AnimatedContent` (iOS's `.contentTransition(.numericText())`), and the end panel fades over 250 ms (web's `fade-in`). All of it collapses to instant when the system animation scale is zero, which is Android's equivalent of `prefers-reduced-motion`.

## Web delivery and base paths

The web app is deployed as static files beneath `/2048-Game/` on GitHub Pages. Canonical URLs, `hreflang` links, the manifest `id`/`start_url`/`scope`, sitemap `<loc>` entries, the `robots.txt` sitemap directive, and Open Graph image URLs must all retain that base path. `scripts/validate-repository.mjs` enforces several of these and will fail the build if they drift.

## Making a parity-safe change

When you change game rules or user-facing behavior:

1. Update the invariant list in [`AGENTS.md`](../AGENTS.md) and this document first, so the contract leads the implementation.
2. Implement in all three clients, or document explicitly why a platform intentionally differs.
3. Add or update the deterministic rules test on each platform.
4. Run `make check` plus every affected platform suite.
5. Capture and visually inspect screenshots for any changed UI state.

Business rules must never move into view-only code on any platform. If a rule is only reachable by rendering a view, it cannot be unit-tested, and parity stops being verifiable.
