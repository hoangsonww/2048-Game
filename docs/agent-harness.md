# Agent harness

This repository is set up so that coding agents across different harnesses read the **same** instructions rather than drifting apart. This document explains how that works and how to work inside it.

## Table of contents

- [How instructions are layered](#how-instructions-are-layered)
- [Harness entry points](#harness-entry-points)
- [Repository-local skills](#repository-local-skills)
- [Recommended sequence](#recommended-sequence)
- [Change discipline](#change-discipline)
- [Scope boundaries](#scope-boundaries)
- [Reporting expectations](#reporting-expectations)
- [Adding or changing a skill](#adding-or-changing-a-skill)

## How instructions are layered

Precedence, highest first:

1. **The user's current request.** Always wins.
2. **The closest scoped `AGENTS.md`** to the files being changed.
3. **The root [`AGENTS.md`](../AGENTS.md)**, the repository source of truth.
4. **The narrowest matching skill** in `.agents/skills/`.
5. **Reference docs** — [`architecture.md`](architecture.md) and [`testing.md`](testing.md).

Canonical content lives in `.agents/skills/`. Every other harness file is a thin adapter that points at it, so a rule is written once and cannot fall out of sync between harnesses.

## Harness entry points

| Harness | Entry point |
| --- | --- |
| Codex and Agent Skills–compatible agents | `AGENTS.md`, `.agents/skills/` |
| Claude Code | `CLAUDE.md`, `.claude/skills/` adapters |
| GitHub Copilot | `.github/copilot-instructions.md` |
| Cursor | `.cursor/rules/project.mdc` |
| Gemini CLI | `GEMINI.md` |
| Windsurf | `.windsurfrules` |

If you add a new harness adapter, point it at `AGENTS.md` and `.agents/skills/` rather than restating rules inline. Duplicated rules are how parity documentation rots.

## Repository-local skills

Load the **narrowest** skill that matches the request:

| Skill | Use for |
| --- | --- |
| `2048-web-development` | Browser UI, engine, accessibility, PWA, or SEO work |
| `2048-ios-development` | SwiftUI, XCTest, persistence, or simulator work |
| `2048-android-development` | Compose, ViewModel, Gradle, or emulator work |
| `2048-cross-platform-parity` | Behavior spanning two or more clients |
| `2048-release-readiness` | Final validation, screenshots, documentation, release checks |

Skills are **task routers, not blanket permission**. Loading the Android skill does not authorize rewriting the Android client — it tells you where things are and which commands to use for the change the user actually asked for.

Any change to game rules or user-facing behavior should load `2048-cross-platform-parity`, because a rules change is by definition a three-client change.

## Recommended sequence

1. Read `AGENTS.md` and inspect `git status --short`.
2. Load the narrowest matching platform skill.
3. Run `make doctor` and `make help` to discover available runtimes and stable entry points. Do not invent one-off commands when a `make` target exists.
4. Make focused changes, running the smallest relevant tests while iterating.
5. Run `make check` plus the complete affected-platform suite before handoff.
6. For UI changes, capture screenshots and **actually look at them**. A blank or clipped frame is a failure, not a pass.
7. Report exact commands, results, artifacts, limitations, and any out-of-scope findings you noticed but did not touch.

## Change discipline

- **Preserve existing user changes in a dirty working tree.** Never reset, discard, stash, or rewrite unrelated work.
- **Treat audit, diagnosis, review, and test-only requests as read-only** unless implementation is explicitly requested.
- **Never claim an unavailable runtime passed.** If `make doctor` reports no Xcode, say the iOS suite could not run — do not infer it from the Android result.
- **Keep game state local.** No backend, analytics, accounts, remote storage, or network calls without explicit product direction.
- **Keep source deterministic** where tests inject a random tile provider.
- **Do not edit generated Xcode project identifiers or Gradle wrapper binaries** unless the task requires it.
- **Never commit** `local.properties`, signing files, tokens, build output, `output/` QA artifacts, or local simulator data. `.gitignore` covers these; do not force-add past it.

## Scope boundaries

The checked-in scripts deliberately avoid external services and production mutation. The following always require explicit authorization and credentials, and must never be performed on an agent's own initiative:

- Pushing to a remote, opening pull requests, or merging
- Creating releases or tags
- Code signing, provisioning, or app store submission
- Publishing packages
- Any operation that sends repository content to an external service

Committing locally is likewise something to do when asked, not by default.

## Reporting expectations

A handoff report should state:

- The exact commands run and their outcomes, quoting real error text rather than paraphrasing it
- Which suites ran and which could not, with the reason (missing toolchain, no device)
- Artifacts produced and where they live
- Known limitations of the change
- Out-of-scope issues noticed but intentionally left alone

If tests failed, say so plainly and include the output. A report that hedges about whether something passed is less useful than one that says it failed.

## Adding or changing a skill

1. Edit the canonical file under `.agents/skills/<name>/SKILL.md`.
2. Confirm the `.claude/skills/` adapter still points at it and does not restate content.
3. Keep skills short and imperative. A skill that grows into a tutorial stops being read.
4. If a rule applies to every platform, it belongs in `AGENTS.md`, not duplicated across five skills.
