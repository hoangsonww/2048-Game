---
name: 2048-android-development
description: Implement or review the Jetpack Compose 2048 app, its ViewModel and storage, Material UI, Gradle build, or emulator tests.
---

# 2048 Android development

Read `AGENTS.md` and the native sections of `docs/architecture.md`. Keep board rules and session state in `GameViewModel.kt`, persistence in `GameStorage.kt`, and presentation in Compose. Preserve deterministic test hooks without weakening production randomness or saved-state validation.

Use Material vector icons and Compose semantics; never use Unicode symbols as controls. Keep tap targets, system insets, contrast, screen-size adaptation, haptics, restart confirmation, help, win continuation, and loss recovery intact.

Run `make test-android` for every change. When UI behavior changes and a device is available, run `make test-android-device`, inspect logcat for app exceptions, and manually review gameplay, help, restart, win, and loss states.
