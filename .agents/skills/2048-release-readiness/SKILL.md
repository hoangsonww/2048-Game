---
name: 2048-release-readiness
description: Perform final release-readiness validation for the 2048 repository, including tests, builds, screenshots, metadata, documentation, and a scoped findings report.
---

# 2048 release readiness

Read `AGENTS.md` and `docs/testing.md`. This is a verification workflow unless the user explicitly requests fixes. Inspect the working tree first and preserve unrelated changes.

Run `make doctor`, `make check`, and every platform suite available on the host. Capture deterministic web states with `make screenshots-web`; use native UI tests or simulator/emulator capture for iOS and Android. Manually inspect gameplay, help/about, restart, victory, and loss states for clipping, contrast, icon geometry, accessibility, and errors.

Also verify canonical URLs, JSON-LD, sitemap, robots, manifest, `llms*.txt`, GitHub workflows, contributor docs, and agent instructions. Report exact pass counts, commands, artifacts, runtime limitations, and flaky harness behavior separately from reproducible product defects. Do not publish, tag, sign, or deploy without explicit authorization.
