---
name: 2048-ios-development
description: Implement or review the native SwiftUI 2048 app, its ViewModel, persistence, accessibility, XCTest coverage, or simulator flows.
---

# 2048 iOS development

Read `AGENTS.md` and the native sections of `docs/architecture.md`. Keep rules and persistence orchestration in `GameViewModel.swift`; keep adaptive presentation in SwiftUI views. Preserve deterministic injection used by tests and production randomness used by the app.

Use SF Symbols for controls, accessibility labels and identifiers for interactive elements, native confirmation and sheet patterns, safe-area-aware layout, Dynamic Type resilience, and reduced-motion behavior where animation exists. Do not replace system icons with text glyphs.

Add focused XCTest coverage for rules/state changes and XCUITest coverage for user-visible flows. Run `make test-ios`; set `IOS_SIMULATOR_ID` when a specific simulator is required. Inspect launch, gameplay, help, restart, win, and game-over states for visible changes.
