# Testing and quality gates

This document describes what is tested, where, how to run it, and how to tell a real defect from a flaky harness. Read it before changing tests or CI.

## Table of contents

- [Testing philosophy](#testing-philosophy)
- [Test inventory](#test-inventory)
- [Fast checks](#fast-checks)
- [Web](#web)
- [iOS](#ios)
- [Android](#android)
- [Determinism](#determinism)
- [Manual UI review](#manual-ui-review)
- [CI mapping](#ci-mapping)
- [Diagnosing failures](#diagnosing-failures)
- [Adding a test](#adding-a-test)

## Testing philosophy

Coverage is layered by cost. Pure rules logic is tested exhaustively because it is cheap, fast, and where correctness actually lives. The expensive suites — a real browser, a booted simulator, a running emulator — are reserved for the things unit tests genuinely cannot reach: gesture handling, persistence across a real relaunch, dialog behavior, focus, and accessibility semantics.

Two consequences follow, and both are deliberate:

- **A rules bug should be caught by a unit test, not a UI test.** If a rules regression is only detected in Chromium or on an emulator, the unit suite has a gap worth closing.
- **A UI test should assert a user-visible outcome**, not re-derive the rules. Duplicating rules assertions in slow suites buys nothing and triples the maintenance cost of every rules change.

## Test inventory

| Platform | Deterministic tests | UI / integration tests | Runner | Line coverage |
| --- | --- | --- | --- | --- |
| Web | 238 engine, controller, cloud, sound, metadata, and asset tests + 2 tooling tests | 13 Chromium scenarios | Node test runner, Playwright | 100 % |
| iOS | 170 model/surface/cloud/profile tests | 13 XCUITest executions | XCTest | 95.1 % domain (gated at 90 %) |
| Android | 193 ViewModel, storage, sound, and surface tests | 20 Compose instrumentation tests | JUnit 4, Compose UI Test | 97.2 % (domain) |
| Cloud API | 76 unit tests | 27 integration tests against a real MongoDB | Node test runner, supertest | — |

The iOS UI suite reports one extra execution because the launch test runs once per appearance mode. The Cloud API integration suite is skipped unless `MONGODB_TEST_URI` is set; see [backend.md](backend.md#local-development).

All three deterministic suites prove the same behavioral contract from [`architecture.md`](architecture.md): every direction, merge ordering and the single-merge rule, scoring, weighted spawning, ineffective moves, undo semantics, restart, best-score retention, win and loss predicates, and rejection of invalid saved state.

Each platform additionally covers the layer above its rules engine:

- **Web** — the controller (`Web-Version/script.js`) runs against a hand-written DOM in `tests/web/helpers/fake-dom.js`, so keyboard, touch, buttons, rendering, and persistence are unit-tested without a browser.
- **iOS** — persistence round-trips, spawn-index clamping, and corrupt `UserDefaults` payloads.
- **Android** — `SharedPreferencesGameStorage` serialisation against an in-memory `SharedPreferences`.
- **Both native clients** — the server-driven surface layer: decoding, version gating, node pruning, source fallback, and the rule that every failure mode ends at the app's own native UI. The shipped `help.json` payload is validated like any other untrusted input, and a test asserts the iOS and Android copies have not drifted apart.
- **Cloud clients (all three platforms)** — fake-transport unit tests for auth, token refresh, sync resolutions, and the guest-prompt / controller state machine. The live API is covered by `server/` unit and integration suites, not by device tests.
- **Guest and account profiles (all three platforms)** — that signing in parks the guest round rather than uploading it, that playing signed in never writes to the guest slot, that signing out restores the guest round byte for byte, and that career statistics are never lifted from local storage. See [Profile separation](#profile-separation).
- **Sound (all three platforms)** — that cues are dropped rather than queued when they cannot be played now. See [Sound timing](#sound-timing).

Every suite enforces its own coverage floor; see the platform sections below.

## Fast checks

Run `make check` before committing. It validates:

- JavaScript syntax across the engine, web script, and all `scripts/*.mjs`
- JSON well-formedness for `manifest.json` and configuration files
- Repository structure and the required npm script surface
- SEO and discovery metadata — canonical URLs, `sitemap.xml` entries, the `robots.txt` sitemap directive, `llms.txt` availability
- Referenced asset existence, including every icon named by the manifest and `index.html`
- Staged-file whitespace, when invoked through Husky
- Every shell script in `scripts/` and `.husky/`, when ShellCheck is installed

ShellCheck is optional locally but **required in CI**. Install it (`brew install shellcheck`, or `apt-get install shellcheck`) to catch shell issues before pushing rather than after.

This is the same command the Husky `pre-commit` hook runs, so a clean `make check` means a clean commit.

## Web

```bash
npx playwright install chromium   # one-time
make test-web                     # or: npm test
```

`make test-web` runs, in order: syntax checks, repository validation, deterministic engine tests with enforced coverage, repository tooling tests, and real Chromium interaction flows.

**Coverage is a hard gate.** `c8` fails the build below 100 % statements, 100 % lines, 100 % functions, or 95 % branches, measured against everything in `Web-Version/`. Both files currently reach 100 % statements, lines, and functions with 98.8 % branches. If you add web code, add the tests that keep it above the line — lowering the thresholds is not the fix.

The controller is an IIFE that reads the document once on load, so `tests/web/helpers/fake-dom.js` stands in for the page: it captures the elements the controller looks up, records the listeners it registers, and lets a test fire a keypress, a swipe, or a click and read the result back. Each `loadController()` call re-requires the module, so tests never share state. The globals it installs are restored around every interaction, which is what keeps two loaded controllers independent.

The thirteen Chromium scenarios cover arrow-key play, WASD play, touch swipe, the on-screen direction pad, undo, persistence across reload, restart confirmation, fullscreen, the win overlay, the loss overlay, recovery from a corrupt saved state, sound timing, account and password flows, and responsive layout from a 320 px phone through tablet widths.

Browser tests drive the page through real input events and read state back through `window.render_game_to_text()`. Keep that hook accurate when the state shape changes, or the browser suite silently loses its assertions.

Screenshots:

```bash
make screenshots-web
make screenshots-mobile       # requires booted iOS + Android runtimes
```

`make screenshots-web` captures deterministic desktop and mobile views of gameplay, the restart dialog, win, loss, About, and the cloud surfaces. `make screenshots-mobile` drives the native clients through accessibility-labelled controls and promotes their game, guest, auth, handover, reset, and leaderboard states. The QA-only variants keep reproducible evidence under `output/playwright/latest/` and `output/mobile/`; those directories are gitignored and must not be committed.

## iOS

```bash
make test-ios
```

Requires macOS with Xcode. The script selects an available iPhone simulator automatically; pin a specific device by setting `IOS_SIMULATOR_ID` to a UDID from `xcrun simctl list devices available`.

Model tests and UI tests run as separate targets (`Game-2048Tests` and `Game-2048UITests`) so a UI-harness failure never masks a rules regression. Preserve the `.xcresult` bundle when diagnosing a failure — it carries the failure screenshots, the full test log, and coverage data that the console output does not.

**Coverage is a hard gate.** After the run, `scripts/test-ios.sh` reads the `.xcresult` with `xccov` and fails below 90 % line coverage of stable app/domain code, currently 95.1 %. `GameView.swift` and `CloudViews.swift` are excluded from the numeric gate because Xcode versions expose materially different generated executable-line counts for SwiftUI view builders. Their behavior is covered by the simulator suite, the same posture Android takes for `MainActivity` and `CloudUi`. Override the floor with `IOS_MINIMUM_COVERAGE` only to raise it.

**Coverage must be measured on both suites together.** The local script runs one combined `xcodebuild test`, and CI — which runs the two targets separately so a UI-harness failure cannot mask a rules regression — collects coverage from both and merges the result bundles with `xcrun xcresulttool merge` before gating. UI-driven paths outside the excluded SwiftUI presentation files therefore still contribute to the domain gate.

New test files must be added to the `Game-2048Tests` target in `2048 Game.xcodeproj` — the project does not use synchronised file groups, so a file that is merely on disk is silently never compiled or run.

XCUITest depends on accessibility identifiers. If a UI test starts failing after a view change, confirm the identifier still exists before assuming the behavior broke.

## Android

```bash
make test-android          # unit tests, lint, debug APK
make test-android-device   # adds Compose tests on a connected device
```

**Coverage is a hard gate.** `make test-android` runs `jacocoCoverageVerification`, which fails below 90 % line or 85 % branch coverage of the Kotlin rules engine and its storage (`GameViewModel`, `GameStorage`, `SavedGame`, `SharedPreferencesGameStorage`, and the `sdui` package). Those currently sit at 97.2 % lines and 85.7 % branches. `SurfaceCatalog` is excluded for the same reason `MainActivity` is — it needs a real `Context`. The HTML report lands in `app/build/reports/jacoco/jacocoTestReport/`.

`MainActivity` is Compose and is deliberately outside that gate: it can only be exercised on a device, which `make test-android-device` does. Holding the whole module to a JVM-only threshold would either fail on every machine without an emulator or push the number down to something meaningless.

The JVM suite needs only the Android SDK 34 — **not a preinstalled JDK.** Gradle 8.13 daemon JVM criteria are committed in `Android-Version/Game2048/gradle/gradle-daemon-jvm.properties`, so Gradle downloads and runs on a matching Adoptium JDK 17 regardless of the machine's default `java`. The first invocation pays a one-time ~180 MB download into `~/.gradle/jdks/`.

`scripts/android.sh` additionally resolves a JDK 17 up front, so both the `make` targets and a raw `./gradlew` work on a machine whose `JAVA_HOME` points at the wrong version.

The instrumentation suite additionally needs a booted emulator or attached device — CI uses an API 34 `pixel_6` image with KVM acceleration and animations disabled.

Animations must be disabled on the device running Compose tests. Enabled animations are the most common cause of intermittent instrumentation failures, and they fail in ways that look like real defects.

## Dev container

The dev container covers the web and Android JVM workflows. Verify it with:

```bash
make verify-devcontainer                   # build the image, check every tool
./scripts/verify-devcontainer.sh --build   # also build the Android client inside it
```

The `--build` form works on an isolated `git archive` copy rather than mounting the working tree. That matters: mounting the live repo means a container build and a host build write to the same `app/build/` directory at the same time, which produces confusing `packageDebug FAILED` errors that look like real defects but are pure contention. Never run both concurrently against the same tree.

**iOS is not containerizable.** Xcode is macOS-only and its license forbids redistribution, so iOS builds and simulator tests always require a macOS host. `make doctor` reports this honestly rather than pretending the suite was skipped for another reason.

## Emulator health retries

The Compose instrumentation suite runs on a hosted runner, where the emulator
occasionally comes up degraded — the console fails to start, `adb` retries
during boot, and the app process never hosts a Compose hierarchy. That
presents as `IllegalStateException: No compose hierarchies found in the app`
from whichever assertion happens to run first, which points at the test
rather than at the device it is waiting on.

Two mitigations, in order:

1. `GameScreenTest.show()` blocks until a Compose root actually registers, so
   a *slow* launch waits instead of failing.
2. [`scripts/ci-emulator-tests.sh`](../scripts/ci-emulator-tests.sh) retries
   the instrumentation run **once**, and only when the log carries an
   emulator-health signature (`No compose hierarchies found`, `Failed to start
   Emulator console`, `INSTALL_FAILED`, `Test run failed to complete`,
   `Unable to find instrumentation`, `Could not access the Package Manager`).

A third layer sits above both, because the first two can only help once the
emulator exists. The action provisions it — SDK download, AVD creation, boot —
before the script is reached, and that provisioning fails on its own
occasionally (`Error on ZipFile unknown archive` from a corrupt package
download). The step therefore gets one more attempt, gated on evidence rather
than on assumption: if a connected-test **result file** exists, the suite ran
and the failure is real, so it fails immediately. Only when nothing was
reported at all — meaning the suite never started — is the environment
retried. A failing test can never reach the second attempt.

That logic lives in a script rather than inline workflow YAML because
`reactivecircus/android-emulator-runner` runs its `script:` input **one line at
a time, each in its own `sh -c`**. No variable survives between lines, and a
multi-line `while` or `if` is split mid-statement and fails with
`Syntax error: end of file unexpected`. Single-line commands are the only
thing that input can express directly.

The second is deliberately narrow. A failing assertion looks nothing like
those signatures and fails on the first attempt — a retry that caught
everything would convert a real regression into an intermittent one, which is
worse than the flake it was meant to solve.

## Gesture ownership

Every client has now shipped a bug where a board swipe reached the surrounding container instead of the game, and each had a different cause. These are the guards:

- **Web:** a browser test asserts the board sets `touch-action: none`, that a `touchmove` starting on the board is `defaultPrevented`, that one starting elsewhere is **not**, and that `touchcancel` releases the suppression.
- **iOS:** a UI test asserts `app.scrollViews` is empty, that the `"Make space."` title's frame does not move during a swipe, and that a valid vertical swipe enables Undo. Anchor on chrome *outside* the board: the container can move while the board's own frame appears stable.
- **Android:** the Compose suite drives real swipes; the board must consume each pointer change so the parent scroll never sees it.

When a swipe bug is reported, measure before theorising. Frame coordinates and the enabled state of Undo tell you whether input reached the game at all — a swipe that scrolls the page and a swipe that silently does nothing look identical to a user, and the second is the more serious defect.

## Profile separation

A device holds two independent rounds — the guest one and the signed-in one —
and the bug class here is leakage in either direction: an account inheriting a
board it never played, or a session overwriting the round a player had before
they signed in. Both are silent, and both are only visible a step later, when
the numbers on the account panel do not match anything the player did.

Each client asserts the same five properties against its own storage:

1. Starting a session parks the guest round untouched, and the account starts
   on a clean board with no best score borrowed from the device.
2. Playing signed in writes only to the account slot.
3. Ending a session restores the guest round exactly — board, score, moves,
   and best score — and clears the cached account round.
4. A sign-in offers the server a **null** save, so nothing local can reach the
   account.
5. Career totals render the account's own figures, even when the device holds
   a much higher local best.

The web suite drives these through `window.Game2048Game`, iOS through
`GameViewModel` against a scratch `UserDefaults` suite, and Android through
two prefixed `SharedPreferencesGameStorage` slots over one fake preferences
file. The warning dialog itself is covered at the UI level on all three:
Playwright, XCTest's confirmation dialog, and the Compose suite.

## Credential entry

Three properties, asserted per client:

1. The confirmation field exists on sign-up and not on sign-in, and a
   mismatch is refused **before** any request is made.
2. A reveal control flips only its own field, and closing a form hides every
   password again.
3. A reset sends the username, the email, and the new password; a refusal
   keeps the form open with the reason on it, and a success revokes the
   session this device held and lands the player back on sign-in.

Web covers these in `account-ui.test.js` plus a Playwright pass over the real
`<dialog>` stacking and the input `type` flip. iOS and Android assert the
controller and API halves on the JVM / in XCTest, and the sheets themselves
in the Compose and XCUITest suites. The server's own reset rules — that a
mismatched pair is refused, that the refusal is indistinguishable from an
unknown account, and that every session dies — are in
`server/tests/integration/api.test.js`, which needs `MONGODB_TEST_URI`.

## Sound timing

The defect these guard is not "no sound" — it is sound arriving late and all
at once. Silence is easy to notice; a backlog is easy to ship.

- **Web:** a Playwright test instruments `AudioContext`, asserts no context
  exists before the first gesture, that the one built inside a gesture is
  already running, that nothing is ever scheduled against a stopped clock, and
  that twelve cues land on at least six distinct clock readings rather than
  one. The unit suite covers the voice cap and the drop-rather-than-queue rule.
- **iOS:** the cue renderer is a pure `nonisolated` function, so the envelope,
  the frequency slide, and the degenerate zero-length case are testable with
  no audio device.
- **Android:** the mixer writes through an injected `ToneSink`, so a JVM test
  can pace it like a real `AudioTrack` and assert that two hundred cues
  produce a fraction of a second of audio rather than ten seconds of backlog.

## Determinism

Every deterministic suite injects its own random provider, so tile spawning is fully reproducible. Never write a rules test that depends on real randomness, and never make the injectable provider the production default.

Tests may also drive state through launch arguments (iOS) or launch state (Android) to reach a specific board — for example a nearly-lost board — without playing dozens of moves to get there. Prefer that over long scripted move sequences: it is faster and it fails more legibly.

## Manual UI review

Automated coverage does not replace looking at the screen. `make screenshots-web` captures browser states at desktop and mobile widths; `make screenshots-mobile` captures the native equivalents from a simulator and emulator. Both promote the canonical set into `images/`:

| Gameplay | Restart confirmation | Win |
| :---: | :---: | :---: |
| ![Normal gameplay with guest invite and cloud controls](../images/web-version-UI.png) | ![The confirmation dialog shown before replacing an active round](../images/web-restart-dialog.png) | ![The win overlay after reaching 2048](../images/web-win.png) |

| Game over | Mobile layout | About |
| :---: | :---: | :---: |
| ![The game-over overlay on a locked board](../images/web-loss.png) | ![The mobile layout with on-screen direction controls](../images/web-mobile-gameplay.png) | ![The rules and strategy page](../images/web-about.png) |

| Guest invite | Create account | Leaderboard |
| :---: | :---: | :---: |
| ![Guest banner above the board](../images/web-cloud-guest.png) | ![Create-account dialog](../images/web-cloud-signup.png) | ![Leaderboard dialog](../images/web-cloud-leaderboard.png) |

| Account panel | Android guest | Android auth sheet |
| :---: | :---: | :---: |
| ![Signed-in account panel](../images/web-cloud-account.png) | ![Android guest banner](../images/android-cloud-guest.png) | ![Android create-account sheet](../images/android-cloud-signup.png) |

| iOS auth sheet | iOS handover | Native password reset |
| :---: | :---: | :---: |
| ![iOS create-account sheet](../images/ios-cloud-signup.png) | ![iOS warning shown before setting the guest round aside](../images/ios-cloud-handover.png) | ![Android password-reset sheet](../images/android-cloud-reset.png) |

For every changed surface, inspect normal gameplay, help/about, restart confirmation, win, game-over, and any touched cloud dialogs where applicable, and check:

- Compact and large breakpoints
- Icon centering, at every icon, by geometry rather than font metrics
- Text truncation and wrapping at the longest realistic content
- Contrast at every tile value, including the high-value tiles
- Focus order and visible focus indicators
- Touch-target sizes
- Safe areas on iOS and gesture-navigation insets on Android
- Browser console output and native crash logs — a clean-looking screen with console errors is still a failure

UI changes require screenshots of the affected states, attached to the pull request.

## CI mapping

| Job | Runner | Steps |
| --- | --- | --- |
| Web | `ubuntu-latest` | `npm ci`, `npm audit --audit-level=high`, Chromium install, syntax, repository validation, ShellCheck, unit + coverage, tooling, browser flows |
| iOS | `macos-15` | Boot a simulator, `build-for-testing`, model tests with coverage, UI/accessibility tests |
| Android JVM | `ubuntu-latest` | `testDebugUnitTest`, `lintDebug`, `assembleDebug` |
| Android device | `ubuntu-latest` + KVM | API 34 `pixel_6` emulator, `connectedDebugAndroidTest` |
| Dependency review | `ubuntu-latest` | Blocks pull requests introducing known-vulnerable dependencies |

Artifacts uploaded on both success and failure: web coverage reports, iOS `.xcresult` bundles, Android lint and test reports, and the debug APK.

The iOS and Android device jobs are the slow ones. When iterating, run the fast web suite locally and let CI carry the native suites rather than waiting on a local emulator boot for every change.

## Diagnosing failures

**Before reporting an app defect, establish whether it is a harness failure.**

| Symptom | Likely cause | Next step |
| --- | --- | --- |
| ADB loses the view hierarchy mid-run | Emulator/ADB instability | Check `adb logcat`, restart the emulator **without** wiping data, rerun the exact failing test |
| Compose test fails intermittently only | Animations enabled on the device | Disable animations, then rerun |
| XCUITest cannot find an element | Missing or renamed accessibility identifier | Confirm the identifier in the view, not the behavior |
| Browser test times out waiting for state | `render_game_to_text()` shape drifted | Compare the hook output against the assertion |
| Coverage step fails after a refactor | New engine branches are untested | Add the missing cases — do not lower the thresholds |
| Simulator tests fail only in CI | Different default simulator/runtime | Reproduce with the same device the workflow selects |

A test that fails once and passes on rerun with no code change is a flake, and flakes are bugs. File them rather than re-running until green.

## Adding a test

1. Put rules behavior in the **deterministic** suite for each platform — all three, since parity is the point.
2. Put user-flow behavior in the platform UI suite, asserting a user-visible outcome rather than re-deriving the rules.
3. Inject randomness. Never depend on real random spawning.
4. Prefer reaching a target board through injected state over a long scripted move sequence.
5. Name the test after the behavior it protects, not the function it calls — the name is what a future maintainer reads when it fails.
6. Confirm it fails before your fix and passes after. A test that never failed has proven nothing.
7. On iOS, add the file to the `Game-2048Tests` target in the Xcode project. A test file that is only on disk never runs and never fails.

**A valid move always spawns a tile.** Asserting a whole row or board after a move therefore couples the test to wherever the injected provider happens to place that tile. Assert the cells the move itself produced, plus the score, unless the spawn position is deliberately pinned.

**An ineffective move persists nothing.** A persistence test whose swipe is rejected saves no state and quietly proves nothing — assert that the move returned `true` before checking what was stored.
