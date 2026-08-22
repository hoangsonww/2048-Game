---
name: 2048-cross-platform-parity
description: Coordinate gameplay, persistence, UX, or accessibility changes that must remain consistent across the web, iOS, and Android 2048 clients.
---

# 2048 cross-platform parity

Read `AGENTS.md`, `docs/architecture.md`, and the relevant platform skills. Write down the observable behavior before editing, then locate its engine/ViewModel, presentation, persistence, and tests in every affected client.

Preserve the shared rules contract while using native presentation patterns: SVG and browser semantics on web, SF Symbols and SwiftUI accessibility on iOS, Material icons and Compose semantics on Android. Pixel identity is not required; equivalent capability, hierarchy, and feedback are.

Add parallel deterministic cases for rule changes and platform-appropriate UI coverage for flow changes. Run `make check` and each affected `make test-*` target. Report any unavailable toolchain or intentional divergence explicitly instead of treating one passing client as proof for all three.
