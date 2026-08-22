# Agent guide for 2048

This file is the source of truth for coding agents working in this repository. Follow the user’s current request first, then the closest scoped `AGENTS.md`, then this guide.

## Project shape

This repository ships the same 2048 experience in three independent clients:

- Web: static HTML/CSS/JavaScript in `index.html` and `Web-Version/`.
- iOS: SwiftUI app in `Game-2048/`, with XCTest and XCUITest targets.
- Android: Jetpack Compose app under `Android-Version/Game2048/`.

The clients do not share runtime code. When game rules or user-facing behavior changes, inspect all three implementations and either preserve parity or document an intentional platform difference.

Read [docs/architecture.md](docs/architecture.md) before changing state, persistence, or game rules. Read [docs/testing.md](docs/testing.md) before changing tests or CI.

## Commands

- `make help`: list supported workflows.
- `make check`: fast syntax, repository, shell, SEO, and discovery checks.
- `make serve`: serve the web app at `http://localhost:8080`.
- `make test-web`: complete deterministic and browser web suite.
- `make android-run`: build, install, and launch on a device or emulator.
- `make android-build` / `android-install` / `android-devices` / `android-tasks` / `android-clean`.
- `make gradle ARGS="<task>"`: run any other Gradle task with a correct JDK.
- `make test-android`: Android unit tests, lint, and debug APK.
- `make test-android-device`: include Compose tests on a connected device.
- `make ios-run`: build, install, and launch on a simulator.
- `make ios-build` / `ios-boot` / `ios-devices`.
- `make test-ios`: iOS unit and UI tests on an available simulator.
- `make test`: run every suite supported by the current host.
- `make screenshots-web`: capture deterministic desktop/mobile UI states.

Never call `adb`, `xcrun`, or `./gradlew` bare from a script or Make target. Use `scripts/android.sh` and `scripts/ios.sh`, which resolve a JDK 17, an `adb` binary, and a simulator UDID. Bare `adb` is not on `PATH` on a default Android Studio install.

Run the smallest relevant checks while iterating and the complete affected-platform suite before handoff. Do not claim an unavailable native runtime passed.

## Change rules

- Preserve existing user changes in a dirty working tree. Do not reset, discard, or rewrite unrelated work.
- Treat audit, diagnosis, review, and test-only requests as read-only unless the user asks for implementation.
- Do not add a backend, analytics, accounts, remote storage, or network calls without explicit product direction.
- Keep game state local. Validate persisted state before restoring it.
- Keep source code deterministic where tests inject a random tile provider.
- Do not edit generated Xcode project identifiers or Gradle wrapper binaries unless the task requires it.
- Never commit `local.properties`, signing files, tokens, build output, or local simulator data.

## Product invariants

- A valid move compacts tiles, merges equal neighbors once, scores the merged values, and spawns one new `2` or `4`.
- An ineffective move changes nothing, creates no undo snapshot, and spawns no tile.
- Undo restores exactly the board and score before the most recent valid move.
- New game preserves the best score and requires confirmation when a round is active.
- Reaching 2048 presents a win state and allows continued play. A full board with no merge presents game over.
- Corrupt or structurally invalid saved state is discarded safely.

## UI and accessibility

- Use SVG on web, SF Symbols on iOS, and Material vector icons on Android. Never use ASCII, emoji, or Unicode glyphs as button icons.
- Keep icon artwork centered by geometry and layout, with an accessible name on the enclosing control.
- Support keyboard and touch on web, native swipes on mobile, visible focus, reduced motion, and readable contrast.
- A board swipe belongs to the board. It must never scroll, bounce, or pan the surrounding screen, and every direction must register a move. Each client enforces this differently: web sets `touch-action: none` plus a non-passive `touchmove` guard, iOS keeps the board out of any scrolling container, and Android consumes each pointer change so the parent scroll never sees it. All three are covered by tests; see [docs/testing.md](docs/testing.md#gesture-ownership).
- Check compact and large layouts. UI changes require screenshots of affected states and manual visual inspection.

## Documentation and generated artifacts

Keep `.github/README.md`, relevant files in `docs/`, `llms.txt`, and agent guidance accurate when commands or architecture change. Store repeatable utilities in `scripts/`; place local QA output under `output/`. Do not hand-edit generated coverage or build products.

## Repository-local skills

Load the narrowest matching skill from `.agents/skills/`:

- `2048-web-development`: browser UI, engine, accessibility, PWA, or SEO work.
- `2048-ios-development`: SwiftUI, XCTest, persistence, or simulator work.
- `2048-android-development`: Compose, ViewModel, Gradle, or emulator work.
- `2048-cross-platform-parity`: behavior spanning two or more clients.
- `2048-release-readiness`: final validation, screenshots, documentation, and release checks.
