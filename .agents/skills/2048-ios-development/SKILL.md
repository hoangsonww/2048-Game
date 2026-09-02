---
name: 2048-ios-development
description: Implement or review the native SwiftUI 2048 app, its ViewModel, persistence, accessibility, XCTest coverage, or simulator flows.
---

# 2048 iOS development

Read `AGENTS.md` and the native sections of `docs/architecture.md`. Keep rules and persistence orchestration in `GameViewModel.swift`; keep adaptive presentation in SwiftUI views. Preserve deterministic injection used by tests and production randomness used by the app.

Use SF Symbols for controls, accessibility labels and identifiers for interactive elements, native confirmation and sheet patterns, safe-area-aware layout, Dynamic Type resilience, and reduced-motion behavior where animation exists. Do not replace system icons with text glyphs.

Never place the board inside a `ScrollView`. A scroll view's pan is a UIKit recogniser and outranks the board's SwiftUI `DragGesture`, so vertical swipes stop reaching the game entirely — and neither `.highPriorityGesture` nor `.scrollBounceBehavior` changes that. The layout is sized to fit, with `ViewThatFits(in: .vertical)` as the fallback; if you add vertical content, keep the static branch fitting and confirm `app.scrollViews` stays empty.

Add focused XCTest coverage for rules/state changes and XCUITest coverage for user-visible flows. Run `make test-ios`; set `IOS_SIMULATOR_ID` when a specific simulator is required. `make ios-run` builds, installs, and launches on a resolved simulator without opening Xcode. Inspect launch, gameplay, help, restart, win, and game-over states for visible changes.
