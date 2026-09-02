# Support

This is a free, open-source project maintained in spare time. There is no backend service, no account system, and no paid support channel — but questions and reports are genuinely welcome, and routing them to the right place gets them answered faster.

## Where to go

| What you have | Where it goes |
| --- | --- |
| A reproducible bug | [Bug report form](https://github.com/hoangsonww/2048-Game/issues/new?template=bug_report.yml) |
| An idea or improvement | [Feature request form](https://github.com/hoangsonww/2048-Game/issues/new?template=feature_request.yml) |
| A setup, build, or development question | [GitHub Discussions](https://github.com/hoangsonww/2048-Game/discussions) |
| A suspected security vulnerability | [Private security advisory](https://github.com/hoangsonww/2048-Game/security/advisories/new) — **never** a public issue |
| A question about contributing | [`CONTRIBUTING.md`](CONTRIBUTING.md), then Discussions |

## Before opening an issue

A few minutes here usually saves a round trip:

1. **Search existing issues**, including closed ones. Parity bugs in particular tend to recur under different descriptions.
2. **Check [Troubleshooting](README.md#troubleshooting)** in the README — it covers the common build and toolchain failures (missing Chromium, no simulator, `ANDROID_HOME` unset, port 8080 in use).
3. **Run `make doctor`** if the problem is environmental. Its output tells you and us which toolchains are actually present.
4. **Confirm which client is affected.** The web, iOS, and Android apps share no runtime code, so "2048 is broken" is three different investigations.

## What makes a good bug report

- The affected client — web, iOS, or Android — and the version or commit
- Platform details: browser and version, or iOS/Android version and device or simulator model
- Exact steps to reproduce, ideally starting from a fresh game
- What you expected versus what happened
- A screenshot or short recording for anything visual
- Browser console output or native crash log if there is any

For rules and gameplay bugs, the board state matters enormously. On the web client, paste the output of `render_game_to_text()` from the browser console — it captures the exact board, score, and available moves in one line, which is far more useful than a description of the board.

## Response expectations

This is a spare-time project, so response times vary. Actionable reports with clear reproduction steps get looked at first. Security reports are prioritized above everything else.

An issue may be closed as informational if it is a generic automated scan result with no demonstrated impact, a question already answered in the documentation, or a request that conflicts with the project's stated constraints — no backend, no accounts, no analytics, no runtime dependencies on the web client.

## Never post in public

Credentials, tokens, signing keys, provisioning profiles, or personal information. If you have already posted something sensitive, delete it and rotate the secret — deleted GitHub content can persist in caches and notification emails.
