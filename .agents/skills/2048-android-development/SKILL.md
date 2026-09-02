---
name: 2048-android-development
description: Implement or review the Jetpack Compose 2048 app, its ViewModel and storage, Material UI, Gradle build, or emulator tests.
---

# 2048 Android development

Read `AGENTS.md` and the native sections of `docs/architecture.md`. Keep board rules and session state in `GameViewModel.kt`, persistence in `GameStorage.kt`, and presentation in Compose. Preserve deterministic test hooks without weakening production randomness or saved-state validation.

Use Material vector icons and Compose semantics; never use Unicode symbols as controls. Keep tap targets, system insets, contrast, screen-size adaptation, haptics, restart confirmation, help, win continuation, and loss recovery intact.

The board's `detectDragGestures` must consume each `PointerInputChange`. The root column scrolls vertically, so an unconsumed change reaches the parent scroll too and a board swipe drags the whole screen. Keep tile animation aligned with the web and iOS timings documented in `docs/architecture.md`, and keep it collapsing to instant when the system animation scale is zero.

No JDK is required: Gradle provisions its own from `gradle/gradle-daemon-jvm.properties`. Use the `make android-*` targets or `Scripts`-equivalent wrappers rather than calling `./gradlew` or `adb` bare — `adb` is not on `PATH` after a default Android Studio install.

Run `make test-android` for every change. When UI behavior changes and a device is available, run `make test-android-device`, inspect logcat for app exceptions, and manually review gameplay, help, restart, win, and loss states. `make android-run` builds, installs, and launches in one step.
