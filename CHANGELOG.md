# Changelog

All notable changes to this project are documented here.

The version applies to all three clients at once: the web app, the iOS app, and
the Android app ship from one `VERSION` file, so a release number means the same
thing everywhere. See [docs/releasing.md](docs/releasing.md).

## Unreleased

- Allow the deployed Netlify client through the Cloud API's production CORS
  policy, with regression coverage for the login preflight.
- Publish a patch release automatically after every pull request merged into
  `main`, while retaining manual minor/major releases and dry runs.
- Move the primary README to the repository root and replace the undifferentiated
  badge wall with a grouped overview of the client, API, quality, and delivery
  stack.

## 2.1.0 — 2026-09-19

Optional Cloud API and client accounts. Play stays local-first; an account adds
cross-device save sync, scores, and leaderboards. Express + MongoDB Atlas backend
with OpenAPI 3.1 (Swagger UI, Redoc, Scalar), wired into web, iOS, and Android.
See [docs/backend.md](docs/backend.md) and [docs/privacy.md](docs/privacy.md).

## 2.0.1 — 2026-09-05

## 2.0.0 — 2026-09-02

Cross-platform rebuild. The web client, the SwiftUI iOS app, and the Jetpack
Compose Android app all implement the same behavioural contract — identical move,
merge, scoring, undo, win, and game-over rules — with shared documentation, a
`make`-driven workflow, and per-client test suites.

## 1.1.0 — 2025-06-30

Web client with persistent best score, undo, keyboard and touch input, and the
About page.
