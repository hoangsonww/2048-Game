# Contributing

Thank you for improving 2048. Contributions of every size are welcome — a typo fix is as valid as a new platform feature.

The one thing this project asks above all else: **keep the three clients behaving identically.** Everything below exists to make that easy rather than tedious.

## Table of contents

- [Quick start](#quick-start)
- [What to work on](#what-to-work-on)
- [The behavior contract](#the-behavior-contract)
- [Making a change](#making-a-change)
- [Code style](#code-style)
- [UI and accessibility changes](#ui-and-accessibility-changes)
- [Testing requirements](#testing-requirements)
- [Commit hooks](#commit-hooks)
- [Commit messages](#commit-messages)
- [Pull requests](#pull-requests)
- [What not to commit](#what-not-to-commit)
- [Review expectations](#review-expectations)

## Quick start

1. Install Node.js 22 and JDK 17. Xcode is needed only for iOS work.
2. Run `make setup`, or reopen the repository in its dev container.
3. Run `make doctor` to see which platform toolchains this machine supports.
4. Run `make help` for the full command list.
5. Create a branch and make the smallest coherent change.

On Linux, iOS is reported as unavailable rather than silently skipped or emulated — that is intentional. Never report a suite as passing when its toolchain was not present.

## What to work on

Good first contributions:

- Bug fixes with a reproducible case, especially parity bugs where one client behaves differently from the other two
- Accessibility improvements — contrast, focus order, screen-reader labels, touch targets
- Test coverage for an uncovered branch
- Documentation corrections and clarifications

Please open an issue before starting on:

- New gameplay features or rule changes
- Board sizes other than 4×4
- Anything that adds a runtime dependency, a build step, or a network call

The web client is deliberately dependency-free and buildless. Proposals that change that need a discussion first, not a pull request first.

## The behavior contract

Every client must satisfy all of these. They are the definition of "correct" in this repository:

- A valid move shifts all tiles, merges each tile **at most once per move**, updates the score by the merged values, and spawns exactly one `2` (90 %) or `4` (10 %).
- An ineffective move changes nothing — no score change, no new tile, **no undo snapshot**.
- Undo restores exactly the board and score from immediately before the last valid move, and is strictly one step.
- New game preserves the best score and requires confirmation while a round is in progress.
- Reaching 2048 offers both a fresh game and continued play. A locked board offers a fresh game.
- Invalid persisted data is validated, rejected, and discarded safely rather than restored or crashed on.

Any intentional platform difference must be stated explicitly in the pull-request description. The full rationale and algorithm detail live in [`docs/architecture.md`](../docs/architecture.md).

## Making a change

For a rules or behavior change, work in this order:

1. **Update the contract first** — [`AGENTS.md`](../AGENTS.md) and [`docs/architecture.md`](../docs/architecture.md) — so the specification leads the code.
2. **Implement in all three clients**, or document why one intentionally differs.
3. **Add or update the deterministic test on each platform.**
4. **Run `make check`** plus the complete suite for every platform you touched.
5. **Capture screenshots** for any changed UI state and look at them.

For a single-platform change (a web-only layout fix, an iOS-only gesture tweak), steps 2 and 3 narrow to that platform — but confirm first that the change genuinely has no cross-client implication.

## Code style

There is no autoformatter enforced in CI, so match the surrounding code rather than introducing a new style:

- `.editorconfig` defines indentation and line endings — most editors apply it automatically.
- **Web:** plain ES modules, no transpilation, no runtime dependencies. Keep `game-engine.js` pure and side-effect free so it stays testable from Node.
- **iOS:** idiomatic SwiftUI. Keep game logic in the view model, not the view.
- **Android:** idiomatic Compose with a `ViewModel`. **Board updates must be immutable** — produce a new board rather than mutating in place. In-place mutation has previously broken recomposition and reverse-direction merges at the same time.
- **Shell:** must pass ShellCheck, which CI enforces.
- Match the existing comment density. This codebase comments *why*, not *what*.

## UI and accessibility changes

Use SVG on web, SF Symbols on iOS, and Material vectors on Android. **Never use Unicode arrows, emoji, or text glyphs as interface icons** — they depend on fonts that may not load and they cannot be centered reliably.

Icons must be centered by geometry and layout, not by font metrics, and the enclosing control must carry an accessible name.

Before submitting, check:

- Compact and wide layouts
- Keyboard focus order and visible focus indicators
- Accessible names on every control
- Touch-target sizes
- Contrast at every tile value, including high-value tiles
- Dynamic type / text scaling
- Reduced-motion behavior
- Safe areas on iOS, gesture-navigation insets on Android
- A clean browser console or native log — visible correctness with console errors is still a failure

Attach before/after screenshots for anything visible.

## Testing requirements

Behavior changes need either a test or a clear manual verification note describing exactly what you checked and on what device.

- Rules behavior belongs in the **deterministic** suite on each platform.
- User-flow behavior belongs in the platform UI suite, asserting a user-visible outcome rather than re-deriving the rules.
- **Inject randomness.** Never write a test that depends on real random spawning.
- Confirm your test fails before the fix and passes after. A test that never failed has proven nothing.
- Web engine coverage is gated at 95 % statements/lines/functions and 90 % branches. If you add engine code, add the tests that keep it above the line — lowering the thresholds is not an acceptable fix.

Full detail, including how to tell a real defect from a flaky emulator, is in [`docs/testing.md`](../docs/testing.md).

## Commit hooks

`npm install` activates Husky:

- **pre-commit** runs the fast repository checks (`make check`)
- **pre-push** runs the full web suite

Python users can install equivalent hooks instead:

```bash
pre-commit install --install-hooks -t pre-commit -t pre-push
```

If a hook blocks you for an unrelated pre-existing failure, say so in the pull request rather than bypassing it silently.

## Commit messages

Write a short imperative subject line describing the effect, not the mechanics:

```
Fix undo restoring an extra move after a blocked swipe
Add reduced-motion handling to Compose tile animations
Document the single-merge rule in architecture.md
```

Explain *why* in the body when the reason is not obvious from the diff. Reference the issue number when there is one.

## Pull requests

- Complete the pull-request template.
- Keep it focused. One logical change per pull request reviews far faster than five bundled together.
- List the exact validation commands you ran and their results.
- State plainly which suites you could **not** run and why (no macOS, no emulator). This is expected and fine — quietly omitting it is not.
- Attach screenshots for UI changes.

CI must pass for web, iOS, Android JVM/lint/build, and Android emulator flows. All four jobs are visible independently, so a failure points straight at the responsible platform.

## What not to commit

`.gitignore` covers these, but do not force-add past it:

- `local.properties`, SDK paths, or any machine-local configuration
- Build output — APKs, `.app` bundles, `DerivedData/`, `build/`, `coverage/`
- Credentials, tokens, signing keys, keystores, or provisioning profiles
- `output/` QA artifacts and screenshots — these are local verification evidence, reproducible with `make test` and `make screenshots-web`
- IDE state beyond the shared module descriptors
- Scratch notes and working files

## Review expectations

Reviews focus on correctness, cross-client parity, accessibility, and test coverage — roughly in that order. Expect questions about parity on anything touching game rules; that is the project's core constraint, not reviewer pedantry.

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). Questions are welcome in [Discussions](https://github.com/hoangsonww/2048-Game/discussions), and [`SUPPORT.md`](SUPPORT.md) explains where each kind of request belongs.
