# Changelog

All notable changes to this project are documented here.

The version applies to all three clients at once: the web app, the iOS app, and
the Android app ship from one `VERSION` file, so a release number means the same
thing everywhere. See [docs/releasing.md](docs/releasing.md).

## Unreleased

## 2.0.0 — 2026-09-02

Cross-platform rebuild. The web client, the SwiftUI iOS app, and the Jetpack
Compose Android app all implement the same behavioural contract — identical move,
merge, scoring, undo, win, and game-over rules — with shared documentation, a
`make`-driven workflow, and per-client test suites.

## 1.1.0 — 2025-06-30

Web client with persistent best score, undo, keyboard and touch input, and the
About page.
