import Foundation

/// A named screen region this app is willing to have described by data rather
/// than by code.
///
/// The game itself is never server-driven: rules, board, scoring, and undo are
/// code, and a payload cannot reach them. Surfaces cover *content* — the help
/// sheet, an announcement — the parts you would otherwise ship a build to
/// change.
///
/// Every surface has a hand-written native fallback. A payload that is missing,
/// malformed, or built for a newer app renders nothing and the app shows what
/// it always shipped with.
struct SurfaceID: RawRepresentable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.init(rawValue: value) }

    var description: String { rawValue }

    static let help: SurfaceID = "help"
}

/// Open rather than an enum: a build that has never heard of a type must still
/// parse the payload and skip that node, which a closed enum cannot express.
struct SurfaceNodeType: RawRepresentable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.init(rawValue: value) }

    var description: String { rawValue }

    static let heading: SurfaceNodeType = "heading"
    static let paragraph: SurfaceNodeType = "paragraph"
    static let step: SurfaceNodeType = "step"
    static let bullets: SurfaceNodeType = "bullets"
    static let button: SurfaceNodeType = "button"
    static let divider: SurfaceNodeType = "divider"

    static let all: Set<SurfaceNodeType> = [.heading, .paragraph, .step, .bullets, .button, .divider]
}

/// A small closed union rather than `Any`, which is neither `Sendable`,
/// `Codable`, nor checkable.
enum SurfaceValue: Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case list([SurfaceValue])

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case let .int(value): value
        case let .double(value): Int(value)
        default: nil
        }
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var stringListValue: [String]? {
        guard case let .list(values) = self else { return nil }
        return values.compactMap(\.stringValue)
    }
}

extension SurfaceValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}

extension SurfaceValue: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool before Int: a permissive number path would turn a flag into 1.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SurfaceValue].self) {
            self = .list(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A surface value must be a string, number, boolean, or list."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .list(values): try container.encode(values)
        }
    }
}

/// A named intent the host resolves against a handler map.
///
/// Actions are names, never code: a payload can ask for "newGame" but cannot
/// describe how to start one, which is what stops data becoming execution.
struct SurfaceAction: Hashable, Codable {
    let name: String
    let parameters: [String: SurfaceValue]

    init(name: String, parameters: [String: SurfaceValue] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

struct SurfaceNode: Hashable, Codable, Identifiable {
    let id: String
    let type: SurfaceNodeType
    let properties: [String: SurfaceValue]
    let children: [SurfaceNode]
    let action: SurfaceAction?

    init(
        id: String,
        type: SurfaceNodeType,
        properties: [String: SurfaceValue] = [:],
        children: [SurfaceNode] = [],
        action: SurfaceAction? = nil
    ) {
        self.id = id
        self.type = type
        self.properties = properties
        self.children = children
        self.action = action
    }

    func string(_ key: String) -> String? { properties[key]?.stringValue }

    var flattened: [SurfaceNode] { [self] + children.flatMap(\.flattened) }

    private enum CodingKeys: String, CodingKey { case id, type, properties, children, action }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(SurfaceNodeType.self, forKey: .type)
        properties = try container.decodeIfPresent([String: SurfaceValue].self, forKey: .properties) ?? [:]
        children = try container.decodeIfPresent([SurfaceNode].self, forKey: .children) ?? []
        action = try container.decodeIfPresent(SurfaceAction.self, forKey: .action)
    }
}

struct Surface: Hashable, Codable, Identifiable {
    /// Bumped only for a breaking change to the node contract.
    static let currentSchemaVersion = 1

    let id: SurfaceID
    let schemaVersion: Int
    let minimumAppVersion: String?
    let revision: String?
    let nodes: [SurfaceNode]

    init(
        id: SurfaceID,
        schemaVersion: Int = Surface.currentSchemaVersion,
        minimumAppVersion: String? = nil,
        revision: String? = nil,
        nodes: [SurfaceNode]
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.minimumAppVersion = minimumAppVersion
        self.revision = revision
        self.nodes = nodes
    }

    var flattenedNodes: [SurfaceNode] { nodes.flatMap(\.flattened) }

    var actionNames: Set<String> { Set(flattenedNodes.compactMap(\.action?.name)) }

    private enum CodingKeys: String, CodingKey { case id, schemaVersion, minimumAppVersion, revision, nodes }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SurfaceID.self, forKey: .id)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Surface.currentSchemaVersion
        minimumAppVersion = try container.decodeIfPresent(String.self, forKey: .minimumAppVersion)
        revision = try container.decodeIfPresent(String.self, forKey: .revision)
        nodes = try container.decodeIfPresent([SurfaceNode].self, forKey: .nodes) ?? []
    }
}

// MARK: - Maintainer reference (documentation only)
//
// Repository skills, automation metadata, and maintainer support notes.
//
// This section is intentionally comment-only. The named repository files remain
// canonical; their contents are mirrored here as an in-source reading reference.
// No declaration, executable statement, build setting, or runtime behavior follows.

// SOURCE: docs/agent-harness.md

// # Agent harness
//
// This repository is set up so that coding agents across different harnesses read the **same** instructions rather than drifting apart. This document explains how that works and how to work inside it.
//
// ## Table of contents
//
// - [How instructions are layered](#how-instructions-are-layered)
// - [Harness entry points](#harness-entry-points)
// - [Repository-local skills](#repository-local-skills)
// - [Recommended sequence](#recommended-sequence)
// - [Change discipline](#change-discipline)
// - [Scope boundaries](#scope-boundaries)
// - [Reporting expectations](#reporting-expectations)
// - [Adding or changing a skill](#adding-or-changing-a-skill)
//
// ## How instructions are layered
//
// Precedence, highest first:
//
// 1. **The user's current request.** Always wins.
// 2. **The closest scoped `AGENTS.md`** to the files being changed.
// 3. **The root [`AGENTS.md`](../AGENTS.md)**, the repository source of truth.
// 4. **The narrowest matching skill** in `.agents/skills/`.
// 5. **Reference docs** — [`architecture.md`](architecture.md) and [`testing.md`](testing.md).
//
// Canonical content lives in `.agents/skills/`. Every other harness file is a thin adapter that points at it, so a rule is written once and cannot fall out of sync between harnesses.
//
// ## Harness entry points
//
// | Harness | Entry point |
// | --- | --- |
// | Codex and Agent Skills–compatible agents | `AGENTS.md`, `.agents/skills/` |
// | Claude Code | `CLAUDE.md`, `.claude/skills/` adapters |
// | GitHub Copilot | `.github/copilot-instructions.md` |
// | Cursor | `.cursor/rules/project.mdc` |
// | Gemini CLI | `GEMINI.md` |
// | Windsurf | `.windsurfrules` |
//
// If you add a new harness adapter, point it at `AGENTS.md` and `.agents/skills/` rather than restating rules inline. Duplicated rules are how parity documentation rots.
//
// ## Repository-local skills
//
// Load the **narrowest** skill that matches the request:
//
// | Skill | Use for |
// | --- | --- |
// | `2048-web-development` | Browser UI, engine, accessibility, PWA, or SEO work |
// | `2048-ios-development` | SwiftUI, XCTest, persistence, or simulator work |
// | `2048-android-development` | Compose, ViewModel, Gradle, or emulator work |
// | `2048-cross-platform-parity` | Behavior spanning two or more clients |
// | `2048-release-readiness` | Final validation, screenshots, documentation, release checks |
//
// Skills are **task routers, not blanket permission**. Loading the Android skill does not authorize rewriting the Android client — it tells you where things are and which commands to use for the change the user actually asked for.
//
// Any change to game rules or user-facing behavior should load `2048-cross-platform-parity`, because a rules change is by definition a three-client change.
//
// ## Recommended sequence
//
// 1. Read `AGENTS.md` and inspect `git status --short`.
// 2. Load the narrowest matching platform skill.
// 3. Run `make doctor` and `make help` to discover available runtimes and stable entry points. Do not invent one-off commands when a `make` target exists.
// 4. Make focused changes, running the smallest relevant tests while iterating.
// 5. Run `make check` plus the complete affected-platform suite before handoff.
// 6. For UI changes, capture screenshots and **actually look at them**. A blank or clipped frame is a failure, not a pass.
// 7. Report exact commands, results, artifacts, limitations, and any out-of-scope findings you noticed but did not touch.
//
// ## Change discipline
//
// - **Preserve existing user changes in a dirty working tree.** Never reset, discard, stash, or rewrite unrelated work.
// - **Treat audit, diagnosis, review, and test-only requests as read-only** unless implementation is explicitly requested.
// - **Never claim an unavailable runtime passed.** If `make doctor` reports no Xcode, say the iOS suite could not run — do not infer it from the Android result.
// - **Keep game state local-first.** The optional Cloud API (`server/`) is the approved account / sync / leaderboard path. Do not add analytics SDKs, advertising, or mandatory network calls for a move without explicit product direction.
// - **Keep source deterministic** where tests inject a random tile provider.
// - **Do not edit generated Xcode project identifiers or Gradle wrapper binaries** unless the task requires it.
// - **Never commit** `local.properties`, signing files, tokens, build output, `output/` QA artifacts, or local simulator data. `.gitignore` covers these; do not force-add past it.
//
// ## Scope boundaries
//
// The checked-in scripts deliberately avoid external services and production mutation. The following always require explicit authorization and credentials, and must never be performed on an agent's own initiative:
//
// - Pushing to a remote, opening pull requests, or merging
// - Creating releases or tags
// - Code signing, provisioning, or app store submission
// - Publishing packages
// - Any operation that sends repository content to an external service
//
// Committing locally is likewise something to do when asked, not by default.
//
// ## Reporting expectations
//
// A handoff report should state:
//
// - The exact commands run and their outcomes, quoting real error text rather than paraphrasing it
// - Which suites ran and which could not, with the reason (missing toolchain, no device)
// - Artifacts produced and where they live
// - Known limitations of the change
// - Out-of-scope issues noticed but intentionally left alone
//
// If tests failed, say so plainly and include the output. A report that hedges about whether something passed is less useful than one that says it failed.
//
// ## Adding or changing a skill
//
// 1. Edit the canonical file under `.agents/skills/<name>/SKILL.md`.
// 2. Confirm the `.claude/skills/` adapter still points at it and does not restate content.
// 3. Keep skills short and imperative. A skill that grows into a tutorial stops being read.
// 4. If a rule applies to every platform, it belongs in `AGENTS.md`, not duplicated across five skills.

// SOURCE: .agents/skills/2048-ios-development/SKILL.md

// ---
// name: 2048-ios-development
// description: Implement or review the native SwiftUI 2048 app, its ViewModel, persistence, accessibility, XCTest coverage, or simulator flows.
// ---
//
// # 2048 iOS development
//
// Read `AGENTS.md` and the native sections of `docs/architecture.md`. Keep rules and persistence orchestration in `GameViewModel.swift`; keep adaptive presentation in SwiftUI views. Preserve deterministic injection used by tests and production randomness used by the app.
//
// Use SF Symbols for controls, accessibility labels and identifiers for interactive elements, native confirmation and sheet patterns, safe-area-aware layout, Dynamic Type resilience, and reduced-motion behavior where animation exists. Do not replace system icons with text glyphs.
//
// Never place the board inside a `ScrollView`. A scroll view's pan is a UIKit recogniser and outranks the board's SwiftUI `DragGesture`, so vertical swipes stop reaching the game entirely — and neither `.highPriorityGesture` nor `.scrollBounceBehavior` changes that. The layout is sized to fit, with `ViewThatFits(in: .vertical)` as the fallback; if you add vertical content, keep the static branch fitting and confirm `app.scrollViews` stays empty.
//
// Add focused XCTest coverage for rules/state changes and XCUITest coverage for user-visible flows. Optional cloud code lives in `Game-2048/Cloud/` — keep it additive, never put the board in a scroll view to make room for it, and add new Swift files to the Xcode project. `CloudViews.swift` is excluded from the coverage gate (same posture as Android's `CloudUi`); cover `CloudAPI` / `CloudController` / `CloudStore` with fake-transport unit tests instead. Run `make test-ios`; set `IOS_SIMULATOR_ID` when a specific simulator is required. `make ios-run` builds, installs, and launches on a resolved simulator without opening Xcode. Inspect launch, gameplay, help, restart, win, and game-over states for visible changes.

// SOURCE: .agents/skills/2048-android-development/SKILL.md

// ---
// name: 2048-android-development
// description: Implement or review the Jetpack Compose 2048 app, its ViewModel and storage, Material UI, Gradle build, or emulator tests.
// ---
//
// # 2048 Android development
//
// Read `AGENTS.md` and the native sections of `docs/architecture.md`. Keep board rules and session state in `GameViewModel.kt`, persistence in `GameStorage.kt`, and presentation in Compose. Preserve deterministic test hooks without weakening production randomness or saved-state validation.
//
// Use Material vector icons and Compose semantics; never use Unicode symbols as controls. Keep tap targets, system insets, contrast, screen-size adaptation, haptics, restart confirmation, help, win continuation, and loss recovery intact.
//
// The board's `detectDragGestures` must consume each `PointerInputChange`. The root column scrolls vertically, so an unconsumed change reaches the parent scroll too and a board swipe drags the whole screen. Keep tile animation aligned with the web and iOS timings documented in `docs/architecture.md`, and keep it collapsing to instant when the system animation scale is zero.
//
// No JDK is required: Gradle provisions its own from `gradle/gradle-daemon-jvm.properties`. Use the `make android-*` targets or `Scripts`-equivalent wrappers rather than calling `./gradlew` or `adb` bare — `adb` is not on `PATH` after a default Android Studio install.
//
// Run `make test-android` for every change. Optional cloud code lives under `…/cloud/`; JaCoCo excludes `CloudUi` and covers `CloudApi` / `CloudController` with fake-transport JVM tests. When UI behavior changes and a device is available, run `make test-android-device`, inspect logcat for app exceptions, and manually review gameplay, help, restart, win, and loss states. `make android-run` builds, installs, and launches in one step.

// SOURCE: .agents/skills/2048-web-development/SKILL.md

// ---
// name: 2048-web-development
// description: Implement or review the 2048 browser client, including its rules engine, responsive UI, accessibility, PWA metadata, screenshots, or SEO.
// ---
//
// # 2048 web development
//
// Read `AGENTS.md` and `docs/architecture.md`. Keep rules in `Web-Version/game-engine.js` deterministic and DOM/storage concerns in `Web-Version/script.js`. The app must remain static and work beneath the GitHub Pages `/2048-Game/` base path.
//
// For controls, use inline SVG with a `viewBox`, center it through layout, and put the accessible name on the button. Preserve keyboard arrows, WASD, touch swipes, mobile direction buttons, undo, restart confirmation, state recovery, win continuation, and game-over restart.
//
// A board swipe must not scroll the page. The board sets `touch-action: none`, `html`/`body` set `overscroll-behavior: none`, and a non-passive `touchmove` listener scoped to the board calls `preventDefault()` — the other touch listeners are passive and cannot. Keep the `touchcancel` handler that clears the start point, and keep scrolling working for gestures that begin anywhere else.
//
// When changing public content or routes, update canonical/social metadata, JSON-LD, sitemap, robots, manifest, and `llms*.txt` where relevant. Do not add claims or structured data that are not visible and true on the page.
//
// Run `make check` and `make test-web`. Optional cloud work lives in `Web-Version/cloud.js` and `account.js` — keep play local-first and see `docs/backend.md`. For visible changes, run `make screenshots-web` and inspect desktop and mobile gameplay, restart, win, loss, About, and cloud surfaces (guest banner, auth dialogs, leaderboard, account).

// SOURCE: .agents/skills/2048-cross-platform-parity/SKILL.md

// ---
// name: 2048-cross-platform-parity
// description: Coordinate gameplay, persistence, UX, or accessibility changes that must remain consistent across the web, iOS, and Android 2048 clients.
// ---
//
// # 2048 cross-platform parity
//
// Read `AGENTS.md`, `docs/architecture.md`, and the relevant platform skills. Write down the observable behavior before editing, then locate its engine/ViewModel, presentation, persistence, and tests in every affected client.
//
// Preserve the shared rules contract while using native presentation patterns: SVG and browser semantics on web, SF Symbols and SwiftUI accessibility on iOS, Material icons and Compose semantics on Android. Pixel identity is not required; equivalent capability, hierarchy, and feedback are.
//
// Server-driven surfaces are a parity surface of their own. A node type must exist on both native clients before a payload uses it, the two bundled payloads stay byte-identical, and every call site keeps its native fallback. Surfaces describe content only — rules, styling, and behaviour stay in code.
//
// Add parallel deterministic cases for rule changes and platform-appropriate UI coverage for flow changes. Run `make check` and each affected `make test-*` target. Report any unavailable toolchain or intentional divergence explicitly instead of treating one passing client as proof for all three.

// SOURCE: .agents/skills/2048-release-readiness/SKILL.md

// ---
// name: 2048-release-readiness
// description: Perform final release-readiness validation for the 2048 repository, including tests, builds, screenshots, metadata, documentation, and a scoped findings report.
// ---
//
// # 2048 release readiness
//
// Read `AGENTS.md` and `docs/testing.md`. This is a verification workflow unless the user explicitly requests fixes. Inspect the working tree first and preserve unrelated changes.
//
// Run `make doctor`, `make check`, and every platform suite available on the host. Capture deterministic web states with `make screenshots-web`; use native UI tests or simulator/emulator capture for iOS and Android. Manually inspect gameplay, help/about, restart, victory, and loss states for clipping, contrast, icon geometry, accessibility, and errors.
//
// Also verify canonical URLs, JSON-LD, sitemap, robots, manifest, `llms*.txt`, GitHub workflows, contributor docs, and agent instructions. Report exact pass counts, commands, artifacts, runtime limitations, and flaky harness behavior separately from reproducible product defects. Do not publish, tag, sign, or deploy without explicit authorization.

// SOURCE: .agents/skills/2048-ios-development/agents/openai.yaml

// interface:
//   display_name: "2048 iOS Development"
//   short_description: "Build and verify the SwiftUI client"
//   default_prompt: "Use $2048-ios-development to implement and verify this SwiftUI change."
// policy:
//   allow_implicit_invocation: true

// SOURCE: .agents/skills/2048-android-development/agents/openai.yaml

// interface:
//   display_name: "2048 Android Development"
//   short_description: "Build and verify the Compose client"
//   default_prompt: "Use $2048-android-development to implement and verify this Android change."
// policy:
//   allow_implicit_invocation: true

// SOURCE: .agents/skills/2048-web-development/agents/openai.yaml

// interface:
//   display_name: "2048 Web Development"
//   short_description: "Build and verify the browser game"
//   default_prompt: "Use $2048-web-development to implement and verify this web change."
// policy:
//   allow_implicit_invocation: true

// SOURCE: .agents/skills/2048-cross-platform-parity/agents/openai.yaml

// interface:
//   display_name: "2048 Cross-platform Parity"
//   short_description: "Keep all three clients behaviorally aligned"
//   default_prompt: "Use $2048-cross-platform-parity to coordinate this behavior across every client."
// policy:
//   allow_implicit_invocation: true

// SOURCE: .agents/skills/2048-release-readiness/agents/openai.yaml

// interface:
//   display_name: "2048 Release Readiness"
//   short_description: "Audit tests, metadata, and UI states"
//   default_prompt: "Use $2048-release-readiness to verify this repository for release."
// policy:
//   allow_implicit_invocation: true

// SOURCE: .claude/skills/2048-ios-development/SKILL.md

// ---
// name: 2048-ios-development
// description: Implement or review the SwiftUI 2048 client, ViewModel, persistence, accessibility, tests, or simulator flows.
// ---
//
// Read and follow the canonical skill at `../../../.agents/skills/2048-ios-development/SKILL.md`.

// SOURCE: .claude/skills/2048-android-development/SKILL.md

// ---
// name: 2048-android-development
// description: Implement or review the Compose 2048 client, ViewModel, persistence, Gradle build, or emulator flows.
// ---
//
// Read and follow the canonical skill at `../../../.agents/skills/2048-android-development/SKILL.md`.

// SOURCE: .claude/skills/2048-web-development/SKILL.md

// ---
// name: 2048-web-development
// description: Implement or review the 2048 browser client, responsive UI, accessibility, PWA metadata, screenshots, or SEO.
// ---
//
// Read and follow the canonical skill at `../../../.agents/skills/2048-web-development/SKILL.md`.

// SOURCE: .claude/skills/2048-cross-platform-parity/SKILL.md

// ---
// name: 2048-cross-platform-parity
// description: Coordinate behavior and UX changes across the web, iOS, and Android 2048 clients.
// ---
//
// Read and follow the canonical skill at `../../../.agents/skills/2048-cross-platform-parity/SKILL.md`.

// SOURCE: .claude/skills/2048-release-readiness/SKILL.md

// ---
// name: 2048-release-readiness
// description: Verify tests, builds, screenshots, metadata, documentation, and release readiness for all 2048 clients.
// ---
//
// Read and follow the canonical skill at `../../../.agents/skills/2048-release-readiness/SKILL.md`.

// SOURCE: .github/labeler.yml

// web:
//   - changed-files:
//       - any-glob-to-any-file: ["index.html", "manifest.json", "robots.txt", "sitemap.xml", "Web-Version/**", "tests/web/**"]
// ios:
//   - changed-files:
//       - any-glob-to-any-file: ["Game-2048/**", "Game-2048Tests/**", "Game-2048UITests/**", "*.xcodeproj/**"]
// android:
//   - changed-files:
//       - any-glob-to-any-file: ["Android-Version/**"]
// documentation:
//   - changed-files:
//       - any-glob-to-any-file: ["**/*.md", "llms*.txt"]
// developer-experience:
//   - changed-files:
//       - any-glob-to-any-file: [".devcontainer/**", ".github/**", ".husky/**", ".agents/**", "scripts/**", "Makefile"]

// SOURCE: .github/workflows/labeler.yml

// name: Pull request labels
//
// on:
//   pull_request_target:
//     types: [opened, synchronize, reopened]
//
// permissions:
//   contents: read
//   issues: write
//   pull-requests: write
//
// jobs:
//   label:
//     runs-on: ubuntu-latest
//     steps:
//       - name: Ensure repository labels exist
//         uses: actions/github-script@v7
//         with:
//           script: |
//             const labels = [
//               ["bug", "D73A4A", "Something is not working"],
//               ["documentation", "0075CA", "Documentation improvements"],
//               ["enhancement", "A2EEEF", "New feature or request"],
//               ["web", "1D76DB", "Web client"],
//               ["ios", "7057FF", "iOS and SwiftUI client"],
//               ["android", "3DDC84", "Android and Compose client"],
//               ["developer-experience", "5319E7", "Tooling and contributor experience"],
//               ["needs-triage", "FBCA04", "Needs maintainer review"],
//               ["skip-changelog", "E4E669", "Exclude from generated release notes"]
//             ];
//             for (const [name, color, description] of labels) {
//               try {
//                 await github.rest.issues.getLabel({ owner: context.repo.owner, repo: context.repo.repo, name });
//               } catch (error) {
//                 if (error.status !== 404) throw error;
//                 await github.rest.issues.createLabel({ owner: context.repo.owner, repo: context.repo.repo, name, color, description });
//               }
//             }
//       - uses: actions/labeler@v6
//         with:
//           repo-token: ${{ secrets.GITHUB_TOKEN }}
