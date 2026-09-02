# 2048 Architecture

This repository ships the same 2048 game three times: as a static web app, as a native SwiftUI iOS app, and as a native Jetpack Compose Android app. **They share no runtime code.** What they share is a behavioural contract, enforced by three independent test suites that assert the same rules.

This document explains why that structure was chosen, what the contract is, and how each client honours it.

New here? Read [The product in one page](#the-product-in-one-page), [Three clients, one contract](#three-clients-one-contract), and [The rules engine](#the-rules-engine). That is enough to follow anything else.

**Structure**

| | |
| --- | --- |
| **Shape** | [Product](#the-product-in-one-page) · [Three clients, one contract](#three-clients-one-contract) · [Why no shared core](#why-there-is-no-shared-core) · [Repository map](#repository-map) · [Decision log](#decision-log) |
| **Rules** | [The rules engine](#the-rules-engine) · [Board representation](#board-representation-and-indexing) · [Move algorithm](#the-move-algorithm) · [Merge ordering](#merge-ordering-the-rule-everyone-gets-wrong) · [A move traced end to end](#a-move-traced-end-to-end) · [Spawning](#tile-spawning-and-determinism) · [Win and loss](#win-and-loss-predicates) · [Complexity](#complexity-and-performance) |
| **State** | [State machine](#game-state-machine) · [Undo](#undo) · [Score](#score-and-best-score) · [Persistence](#persistence-and-corrupt-state) · [State shape reference](#state-shape-reference) |
| **Clients** | [Web](#web-client) · [iOS](#ios-client) · [Android](#android-client) · [Server-driven surfaces](#server-driven-surfaces) · [Input pipeline](#input-pipeline) · [Gesture ownership](#gesture-ownership) · [Rendering](#rendering-pipelines) · [Design tokens](#design-tokens-shared-by-hand) · [Motion](#motion-architecture) |
| **Web surface** | [PWA and discovery](#pwa-and-discovery-surface) |
| **Quality** | [Test strategy](#test-strategy) · [Determinism seams](#determinism-seams) · [The fake DOM harness](#the-fake-dom-harness) · [Coverage gates](#coverage-gates) · [Failure modes](#failure-modes-and-how-each-is-caught) · [Accessibility](#accessibility) |
| **Tooling** | [Command surface](#command-surface) · [Toolchain resolution](#toolchain-resolution) · [Build topology](#build-topology) · [Dev container](#dev-container) · [CI topology](#ci-topology) |
| **Reference** | [Extending across three clients](#extending-across-three-clients) · [Security and privacy](#security-and-privacy-posture) · [Invariants](#architectural-invariants) · [Glossary](#glossary) |

---

## The product in one page

2048 is a sliding-tile puzzle on a 4×4 grid. The player swipes; every tile slides as far as it can in that direction; equal neighbours merge into their sum; one new tile appears. Reach 2048 to win. Fill the board with no merge available to lose.

```mermaid
flowchart LR
    Player([Player])
    subgraph Client[One client: web, iOS, or Android]
        Input[Input layer<br/>keys, touch, buttons]
        Engine[Rules engine<br/>pure functions]
        State[Game state<br/>board, score, history]
        View[Presentation]
        Store[(Local storage)]

        Input --> Engine
        Engine --> State
        State --> View
        State <--> Store
    end

    Player -->|swipe or key| Input
    View -->|board, score, status| Player
```

Everything is local. There is no account, no server, no analytics, no network call. The only persistence is the browser's `localStorage`, iOS `UserDefaults`, and Android `SharedPreferences` — each holding one saved round and one best score.

---

## Three clients, one contract

```mermaid
flowchart TB
    Contract[["Behavioural contract<br/>compaction · single-merge · scoring<br/>spawn · undo · win/loss · save validation"]]

    subgraph Web["Web — JavaScript"]
        WE[game-engine.js<br/>pure, dual-target]
        WC[script.js<br/>DOM controller]
        WC --> WE
    end

    subgraph iOS["iOS — Swift 6 / SwiftUI"]
        IV[GameViewModel.swift<br/>rules + state]
        IU[GameView.swift]
        IU --> IV
    end

    subgraph Android["Android — Kotlin / Compose"]
        AV[GameViewModel.kt<br/>rules + state]
        AU[MainActivity.kt]
        AU --> AV
    end

    WE -.asserts.-> Contract
    IV -.asserts.-> Contract
    AV -.asserts.-> Contract
```

The contract is not a shared library, an interface definition, or a code generator. It is a list of behaviours, written down in this document and in [`docs/testing.md`](docs/testing.md), and independently asserted by a test suite on each platform.

| Contract clause | Web test | iOS test | Android test |
| --- | --- | --- | --- |
| A valid move compacts, merges once, scores, and spawns | ✓ | ✓ | ✓ |
| An ineffective move changes nothing and spawns nothing | ✓ | ✓ | ✓ |
| Undo restores exactly the board and score before the last valid move | ✓ | ✓ | ✓ |
| New game preserves the best score | ✓ | ✓ | ✓ |
| 2048 wins but play continues | ✓ | ✓ | ✓ |
| A full board with no merge is game over | ✓ | ✓ | ✓ |
| Corrupt saved state is discarded safely | ✓ | ✓ | ✓ |

When a rule changes, all three implementations change and all three suites are updated. A change that lands on one platform only is a parity bug, and the [`2048-cross-platform-parity`](.agents/skills/2048-cross-platform-parity/SKILL.md) skill exists to catch exactly that.

### Why there is no shared core

The obvious alternative — one engine compiled to WebAssembly, or a Kotlin Multiplatform module, or a C core with bindings — was rejected. The reasoning:

| Consideration | Why it favours three implementations |
| --- | --- |
| **Size of the shared surface** | The entire rules engine is ~100 lines. A cross-language build system to share 100 lines costs more than it saves, permanently |
| **Onboarding** | A web developer clones this repo and runs `npm test` in seconds. A shared core would mean installing a second toolchain before touching the web app |
| **Idiomatic clients** | Each client uses its platform's natural state primitive — a plain object, `@Published`, `mutableStateOf`. A shared core would force a foreign state model into two of the three |
| **Build independence** | The iOS app builds with no Node. The Android app builds with no Xcode. A broken toolchain on one platform cannot block the other two |
| **The contract is testable anyway** | Three test suites asserting the same behaviour catch divergence just as reliably as a shared binary — and they catch it *per platform*, which is where a bug actually manifests |

The cost is real and is accepted: a rule change is three edits, not one. That is the trade, and it is deliberate.

### Decision log

The decisions that shaped this repository, and what would have to change for each to be revisited.

| # | Decision | Rationale | Would be revisited if |
| --- | --- | --- | --- |
| 1 | Three independent implementations, no shared core | The shared surface is ~100 lines; a cross-language build costs more than it saves, permanently | The rules grew to the point where three implementations genuinely diverged in practice, not just in principle |
| 2 | No framework on the web — no bundler, no transpiler, no runtime dependency | The app is one HTML file, one stylesheet, and two scripts. A build step would add failure modes without removing any | The app needed routing, code splitting, or a component model |
| 3 | Flat 16-element board array rather than nested rows | Copy, compare, and validate become one-liners; the merge function is direction-agnostic | Never — the nested form has no advantage here |
| 4 | Randomness injected as a parameter everywhere | Without it, no test could assert a board after a move | Never; this is load-bearing for the whole test strategy |
| 5 | Rules live in the view model on iOS and Android, not a separate module | A separate module for ~100 lines would add a build target on each platform for no testability gain — the view models are already testable headlessly | The rules grew large enough to warrant their own target |
| 6 | Undo is exactly one step | A single slot is predictable, cheap to persist, and matches the original game | Users asked for deeper history and were willing to pay the persistence complexity |
| 7 | Gradle provisions its own JDK via `gradle-daemon-jvm.properties` | A contributor should not have to install a specific JDK before `make test-android` works | Gradle's toolchain provisioning stopped being reliable |
| 8 | Everything routes through `make` and `scripts/` | `adb` is not on `PATH` after a default Android Studio install, and the default `java` is usually wrong | Never — this is the difference between a clone that works and one that does not |
| 9 | Storage keys are per-platform and idiomatic, not unified | Saves never travel between clients, so a shared format would buy nothing | A cross-device sync feature existed, which would contradict decision 10 |
| 10 | No backend, no accounts, no analytics, no network calls | The game does not need them, and their absence is what makes the privacy posture trivially auditable | Never, without an explicit product decision |

---

## Repository map

```mermaid
flowchart TD
    Root[Game-2048]

    Root --> Web["index.html · Web-Version/<br/>static web app"]
    Root --> IOS["Game-2048/ · 2048 Game.xcodeproj<br/>SwiftUI app"]
    Root --> Droid["Android-Version/Game2048/<br/>Compose app"]
    Root --> Tests["tests/<br/>web + tooling suites"]
    Root --> Scripts["scripts/<br/>toolchain-resolving entry points"]
    Root --> Docs["docs/ · .github/README.md"]
    Root --> Agents[".agents/skills/ · AGENTS.md<br/>agent guidance"]
    Root --> CI[".github/workflows/"]
```

| Path | Holds | Built by |
| --- | --- | --- |
| `index.html`, `Web-Version/` | The static web app: engine, controller, styles | Nothing — it is served as-is |
| `Game-2048/` | SwiftUI views, view model, assets, entitlements | `xcodebuild` via `scripts/ios.sh` |
| `Game-2048Tests/`, `Game-2048UITests/` | XCTest and XCUITest targets | Same |
| `Android-Version/Game2048/` | Compose UI, view model, storage, Gradle build | Gradle via `scripts/android.sh` |
| `tests/web/`, `tests/tooling/` | Node test-runner suites and the fake DOM harness | `node --test` |
| `scripts/` | Every entry point; resolves JDKs, simulators, and `adb` | Invoked by `make` |
| `docs/` | Architecture, testing, and screenshot guides | — |
| `.agents/skills/` | Repository-local agent workflows, mirrored to `.claude/skills/` | — |

There are two `.xcodeproj` directories at the root. **`2048 Game.xcodeproj` is the real one**; `Game-2048.xcodeproj` is a stray with no `project.pbxproj`. Build scripts reference the former explicitly.

---

## The rules engine

Only the web client separates the engine into its own file. On iOS and Android the same logic lives inside the view model — but it is written to be free of view dependencies, which is what lets it be unit-tested without a simulator or emulator.

The web engine is the reference implementation, because it is the one that is genuinely pure:

```mermaid
classDiagram
    class Game2048Engine {
        +SIZE: 4
        +DIRECTIONS: up,down,left,right
        +createEmptyBoard() number[16]
        +isValidBoard(board) bool
        +mergeLine(line) LineResult
        +calculateMove(board, direction) MoveResult
        +addRandomTile(board, random) number[16]
        +isGameOver(board) bool
        +availableMoves(board) string[]
    }
    class LineResult {
        line: number[4]
        gained: number
    }
    class MoveResult {
        board: number[16]
        gained: number
    }
    Game2048Engine ..> LineResult
    Game2048Engine ..> MoveResult
```

Three properties make it testable and portable:

1. **The board is a flat 16-element array**, not a 2×2 nested structure. Index `row * 4 + column`. Flat storage makes copying, comparing, and validating trivial one-liners.
2. **Every function is side-effect free.** `calculateMove` returns a new board and never touches its input — a property directly asserted by a test, because an engine that mutates its argument silently breaks undo.
3. **Randomness is a parameter**, not a global. `addRandomTile(board, random)` defaults to `Math.random` but accepts any generator, which is what makes every spawn-related test deterministic.

The engine is dual-target by construction:

```javascript
(function exposeGameEngine(root, factory) {
    const engine = factory();
    if (typeof module === "object" && module.exports) module.exports = engine;
    if (root) root.Game2048Engine = engine;
})(typeof globalThis !== "undefined" ? globalThis : this, () => { /* … */ });
```

One file, loadable as a `<script>` in the browser and as a CommonJS module in Node. No bundler, no transpiler, no build step. That is why enforced coverage on the rules is cheap here and why the web suite runs in ~150 ms.

### Validation at the boundary

Every public engine function calls `assertBoard` first and throws a `TypeError` on anything malformed. A tile is valid when it is a non-negative integer that is either zero or a power of two:

```javascript
Number.isInteger(value) && value >= 0 && (value === 0 || (value & (value - 1)) === 0)
```

The `value & (value - 1)` trick is the standard power-of-two check. This matters more than it looks: it is the same predicate that rejects corrupt saved state, so a `localStorage` entry someone hand-edited to contain `3` or `-2` or `"2"` is refused by the same code path that validates a live board.

---

## Board representation and indexing

The web engine stores the board as a **flat 16-element array**. iOS and Android use `[[Int]]` / `List<List<Int>>` — nested rows — because that is what reads naturally in a SwiftUI `ForEach` and a Compose `Column`. The flat form is the interesting one, because it is what makes the direction-agnostic merge possible.

```mermaid
flowchart LR
    subgraph Grid["Logical 4×4 grid"]
        direction TB
        R0["(0,0) (0,1) (0,2) (0,3)"]
        R1["(1,0) (1,1) (1,2) (1,3)"]
        R2["(2,0) (2,1) (2,2) (2,3)"]
        R3["(3,0) (3,1) (3,2) (3,3)"]
    end

    subgraph Flat["Flat storage, row-major"]
        direction TB
        F0["0  1  2  3"]
        F1["4  5  6  7"]
        F2["8  9 10 11"]
        F3["12 13 14 15"]
    end

    Grid -->|"index = row × 4 + column"| Flat
```

Line extraction is one pair of expressions covering all four directions:

```javascript
const row    = direction === "left" || direction === "right" ? outer : inner;
const column = direction === "left" || direction === "right" ? inner : outer;
```

For a horizontal move, `outer` is the row and `inner` walks the columns. For a vertical move they swap. That is the entire difference between "move left" and "move up" — the merge itself never knows which it is doing.

| Property | Flat array | Nested rows |
| --- | --- | --- |
| Copy | `[...board]` | `grid.map { it.toList() }` |
| Compare | `a.every((v, i) => v === b[i])` | element-wise nested walk |
| Validate | `board.length === 16 && board.every(isTile)` | check outer length, then each inner |
| Count empties | one `filter` | `flatten().filter` |
| Transpose for a vertical move | index arithmetic, no allocation | build a new column list |

Neither form is wrong. The flat array is chosen on the web because the engine is the thing under test and its operations are all whole-board; the nested form is chosen on the clients because the UI iterates rows.

**The conversion happens once, at the persistence boundary.** Android serialises `grid.flatten().joinToString(",")` and restores with `values.chunked(4)`; iOS stores `grid.flatMap { $0 }` and restores by striding. Both are validated for exactly 16 elements before the chunking happens — which is what turns a truncated write into a clean rejection rather than a misaligned board.

---

## A move traced end to end

A single left swipe on a real board, from key press to persisted state.

Starting board, score 40:

```
2  2  4  0
0  4  0  0
8  8  8  8
2  0  0  2
```

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant C as Controller
    participant E as Engine
    participant S as State
    participant P as localStorage

    U->>C: ArrowLeft
    C->>C: keyMap lookup → "left"
    C->>C: event.preventDefault()
    C->>E: calculateMove(board, "left")

    Note over E: row 0 [2,2,4,0] → [4,4,0,0] gained 4
    Note over E: row 1 [0,4,0,0] → [4,0,0,0] gained 0
    Note over E: row 2 [8,8,8,8] → [16,16,0,0] gained 32
    Note over E: row 3 [2,0,0,2] → [4,0,0,0] gained 4

    E-->>C: {board, gained: 40}
    C->>C: board changed? yes
    C->>S: history = snapshot{board, score, won}
    C->>S: score = 40 + 40 = 80
    C->>S: best = max(best, 80)
    C->>E: addRandomTile(board)
    E-->>S: one 2 or 4 in an empty cell
    C->>C: any tile ≥ 2048? no
    C->>C: isGameOver? no
    C->>P: write {board, score, best, won}
    C->>C: render(animate: true)
    C->>U: "left. Merged for 40 points."
```

Result, score 80, plus one spawned tile:

```
4  4  0  0
4  0  0  0
16 16 0  0
4  0  0  0
```

Three things this trace makes concrete:

- **Row 2 is the single-merge rule in action.** `[8,8,8,8]` becomes `[16,16]`, not `[32]`. Two independent pairs, scoring 16 + 16 = 32.
- **Row 3 merges across a gap.** `[2,0,0,2]` compacts to `[2,2]` first, then merges. Compaction always precedes merging.
- **The score is the sum of created tiles**, not of tiles that moved: 4 + 32 + 4 = 40.

Now the same board swiped **right** instead:

```
0  0  4  4        ← [2,2,4,0] reversed, merged, reversed back
0  0  0  4
0  0 16 16
0  0  0  4
```

Row 0 becomes `[0,0,4,4]` rather than `[4,4,0,0]` — same merge, mirrored destination. Row 2 is symmetric so it looks the same. This is why the reverse-merge-reverse structure is worth the indirection: the asymmetry is handled once.

---

## Complexity and performance

The board is 16 cells. None of this is performance-critical, and the implementation deliberately favours clarity — but the characteristics are worth stating so nobody "optimises" something that is already trivial.

| Operation | Cost | Notes |
| --- | --- | --- |
| `mergeLine` | O(4) | One compaction pass, one merge pass |
| `calculateMove` | O(16) | Four lines × constant work; allocates one new 16-element board |
| `addRandomTile` | O(16) | One pass to collect empty indices, two generator calls |
| `isGameOver` | O(16), short-circuits | Returns immediately if any cell is empty — the common case is one `includes` |
| `availableMoves` | O(4 × 16) | Runs `calculateMove` per direction. Used by the state dump and by tests, not on the hot path |
| Web render | O(16) | Cells are built once, then updated in place |
| Persist | O(16) | One JSON serialise per valid move |

A full move — calculate, spawn, check status, persist, render — is a few hundred operations on 16 integers. The dominant cost in practice is the `localStorage` write, and even that is negligible at this size.

**Rendering is where the only real decision lives.** The web client does not rebuild the DOM per move; it builds 16 cells once and mutates `textContent`, `dataset.value`, `aria-label`, and a class. Rebuilding would be correct and would also destroy focus, break the CSS transition, and re-trigger every animation. There is a test asserting the same cell objects survive a move for exactly this reason.

---

## The move algorithm

Every direction reduces to the same one-dimensional operation. The engine extracts a line, optionally reverses it, merges it toward index 0, reverses back, and writes it home.

```mermaid
flowchart TD
    Start[calculateMove board, direction] --> Assert[assertBoard + direction check]
    Assert --> Loop[For each of 4 lines]
    Loop --> Extract{Direction}
    Extract -->|left / right| Row[Extract row]
    Extract -->|up / down| Col[Extract column]
    Row --> Rev{right or down?}
    Col --> Rev
    Rev -->|yes| Reverse[Reverse line]
    Rev -->|no| Merge
    Reverse --> Merge[mergeLine: compact + merge + pad]
    Merge --> Unrev{was reversed?}
    Unrev -->|yes| Back[Reverse back]
    Unrev -->|no| Write
    Back --> Write[Write into new board]
    Write --> Loop
    Loop --> Done[Return board + gained]
```

`mergeLine` is the whole game in fifteen lines:

```mermaid
flowchart LR
    In["[2,0,2,4]"] --> Compact["filter zeros<br/>[2,2,4]"]
    Compact --> Scan[Walk left to right]
    Scan --> Eq{next equal?}
    Eq -->|yes| Sum["push sum, skip both<br/>gained += sum"]
    Eq -->|no| Keep[push value]
    Sum --> Scan
    Keep --> Scan
    Scan --> Pad["pad with zeros<br/>[4,4,0,0]"]
```

Collapsing four directions into one merge function is the single most important structural decision in the engine. It means merge ordering, the single-merge rule, and scoring are each implemented **once**, so they cannot disagree between directions — a class of bug that plagues naive 2048 implementations.

### Merge ordering: the rule everyone gets wrong

Merging always resolves from the destination edge inward. This is not a stylistic choice; it is observable behaviour that changes the board.

```mermaid
flowchart TB
    subgraph Left["[2,2,2,0] moving LEFT"]
        L1["2 2 2 _"] --> L2["merge the pair nearest the left edge"]
        L2 --> L3["4 2 _ _"]
    end

    subgraph Right["[2,2,2,0] moving RIGHT"]
        R1["2 2 2 _"] --> R2["reverse → merge nearest → reverse back"]
        R2 --> R3["_ _ 2 4"]
    end
```

The same three tiles produce `4 2` moving left and `2 4` moving right. Because the engine reverses the line before merging and reverses the result back, this falls out for free — there is no direction-specific branch anywhere.

Two adjacent rules that are constantly confused:

| Rule | Correct | Wrong |
| --- | --- | --- |
| A merged tile cannot merge again this move | `[2,2,4]` → `[4,4]` | `[2,2,4]` → `[8]` |
| Four equal tiles make two pairs, not a chain | `[2,2,2,2]` → `[4,4]` score 8 | `[2,2,2,2]` → `[8]` score 12 |

Both are directly asserted on all three platforms. The first is the most commonly broken rule in 2048 implementations, which is why it has a dedicated test with that fact in the comment.

---

## Tile spawning and determinism

A **valid** move spawns exactly one tile. An **ineffective** move spawns nothing.

```mermaid
flowchart TD
    Move[Swipe] --> Calc[calculateMove]
    Calc --> Changed{Board changed?}
    Changed -->|no| Reject["Return false<br/>no spawn · no score · no undo snapshot"]
    Changed -->|yes| Snap[Save undo snapshot]
    Snap --> Score[score += gained]
    Score --> Spawn[addRandomTile]
    Spawn --> Status[Update win / game-over]
    Status --> Persist[Save to local storage]
    Persist --> Accept[Return true]
```

The spawn itself takes two rolls from the generator:

```mermaid
flowchart LR
    Roll1[roll 1] --> Clamp["clamp to 0 … 0.999999999"]
    Clamp --> Pick["index = floor roll × emptyCount"]
    Pick --> Cell[Choose empty cell]
    Roll2[roll 2] --> Value{"roll &lt; 0.9?"}
    Value -->|yes| Two[Spawn 2]
    Value -->|no| Four[Spawn 4]
    Cell --> Place[Place value]
    Two --> Place
    Four --> Place
```

Two details that exist because they were tested:

- **The location roll is clamped.** A generator returning exactly `1.0` would compute an index one past the end of the empty list. Clamping to `0.999999999` makes an out-of-range generator impossible to crash on. iOS and Android clamp the index itself (`min(max(index, 0), count - 1)`) for the same reason, and have a test that feeds them `-5` and `999`.
- **The `< 0.9` boundary is exclusive.** A roll of exactly `0.9` produces a **4**, not a 2. All three platforms have a test asserting both sides of that boundary, because an off-by-one here shifts the game's difficulty in a way no casual play would reveal.

### Determinism as a design constraint

Every client injects its randomness:

| Client | Injection point |
| --- | --- |
| Web | `addRandomTile(board, random)` — a parameter with a default |
| iOS | `GameViewModel(randomIndex:randomUnit:)` — two closures |
| Android | `GameViewModel(randomIndex:randomUnit:)` — two lambdas |

This is the single constraint that makes the whole test strategy possible. Without it, no test could assert a board state after a move, and the suites would be reduced to checking that nothing crashed.

**Consequence for test authors:** because a valid move always spawns, asserting a whole row after a move couples the assertion to wherever the injected generator happened to place the tile. Assert the cells the *merge* produced, plus the score. This is written down in [`docs/testing.md`](docs/testing.md) because it broke three tests during development.

---

## Win and loss predicates

```mermaid
flowchart TD
    Board[Board after a move] --> Win{Any tile ≥ 2048?}
    Win -->|yes, first time| Won["hasWon = true<br/>show win overlay<br/>play continues"]
    Win -->|no| Over

    Won --> Over{Any empty cell?}
    Over -->|yes| Playing[Playing]
    Over -->|no| Pairs{Any equal orthogonal neighbours?}
    Pairs -->|yes| Playing
    Pairs -->|no| GameOver[Game over]
```

Two properties worth stating explicitly:

- **Winning does not end the game.** Reaching 2048 shows an overlay offering both "new game" and "keep playing". The win state is sticky — it is announced once and does not re-fire on every subsequent move.
- **Game over requires both conditions.** A full board is not enough; a full board *with* an adjacent equal pair is still playable. Each platform has three tests here: a full board with a horizontal pair, one with a vertical pair, and a true checkerboard lock.

`isGameOver` short-circuits on `board.includes(0)` before scanning for pairs, so the common case is one pass.

---

## Game state machine

```mermaid
stateDiagram-v2
    [*] --> Loading
    Loading --> Playing: valid saved round restored
    Loading --> Fresh: no save, or save rejected
    Fresh --> Playing: two tiles spawned

    Playing --> Playing: valid move
    Playing --> Playing: ineffective move (no state change)
    Playing --> Won: a tile reaches 2048
    Won --> Playing: keep playing
    Playing --> GameOver: board full, no merges

    Playing --> Fresh: new game
    Won --> Fresh: new game
    GameOver --> Fresh: new game

    Playing --> Playing: undo
    Won --> Playing: undo (rewinds the win)
```

Undo from the `Won` state rewinds `hasWon` too — the snapshot captures the win flag alongside the board and score, so undoing the winning move genuinely un-wins.

### Undo

Undo is exactly one step deep, and that is a deliberate product decision rather than a limitation.

```mermaid
sequenceDiagram
    participant P as Player
    participant S as State
    participant H as History (one slot)

    P->>S: swipe (valid)
    S->>H: store {board, score, hasWon}
    S->>S: apply move, spawn, persist
    Note over S,H: canUndo = true

    P->>S: swipe (ineffective)
    Note over S,H: nothing stored, history untouched

    P->>S: undo
    H-->>S: restore snapshot
    S->>S: clear history, persist
    Note over S,H: canUndo = false — the slot is consumed
```

Three rules, all tested on every platform:

1. **An ineffective move creates no snapshot.** Otherwise a blocked swipe would silently consume the player's undo.
2. **The snapshot is consumed.** A second undo is a no-op, not a rewind two moves back.
3. **Undo is persisted.** The undone board is written to storage, so relaunching the app does not resurrect the move.

### Score and best score

```mermaid
flowchart LR
    Merge[Merge creates a tile] --> Gained["gained += new tile value"]
    Gained --> Score[score += gained]
    Score --> Best{score &gt; best?}
    Best -->|yes| Update[best = score, persist]
    Best -->|no| Keep[best unchanged]
```

Only **newly created** tiles score. Sliding without merging scores nothing. `[2,2,8,8]` moving left scores 20 — the 4 and the 16, not the tiles that merely moved.

The best score survives a new game and never decreases. There is a subtle trap here that the web implementation handles explicitly: `mergeLine` accumulates into the score as it runs, so a move that turns out to be ineffective must roll that back. All three clients restore the previous score before returning `false`, and all three have a test asserting a blocked swipe does not inflate the total.

---

## Persistence and corrupt state

Each client stores one saved round and one best score under platform-native keys:

| Client | Mechanism | Round key | Best-score key |
| --- | --- | --- | --- |
| Web | `localStorage` | `game2048-state-v2` (JSON) | `highScore` |
| iOS | `UserDefaults` | `savedGridV2`, `savedScoreV2`, `savedHasWonV2` | `highScore` |
| Android | `SharedPreferences` | `saved_grid_v2` (CSV), `saved_score_v2`, `saved_won_v2` | `high_score` |

The keys are intentionally *not* unified — each is idiomatic for its platform, and the saves never travel between clients. The `v2` suffix marks the current layout; an older `v1` entry is simply not read.

Restoring is the one place the app ingests data it did not create, so every client validates before trusting:

```mermaid
flowchart TD
    Launch[Launch] --> Read[Read saved round]
    Read --> Exists{Present?}
    Exists -->|no| Fresh[Start a fresh round]
    Exists -->|yes| Parse{Parses?}
    Parse -->|no| Discard[Discard and start fresh]
    Parse -->|yes| Shape{16 cells?}
    Shape -->|no| Discard
    Shape -->|yes| Tiles{All powers of two, ≥ 0?}
    Tiles -->|no| Discard
    Tiles -->|yes| Clamp[Clamp score and best to ≥ 0]
    Clamp --> Restore[Restore board, score, win state]
    Restore --> Over{Already game over?}
    Over -->|yes| Panel[Show end-of-round panel]
    Over -->|no| Play[Continue]
```

Every rejection path is tested: unparseable JSON, wrong cell count, non-power-of-two values, negative tiles, non-numeric entries, and negative scores. The failure mode is always the same — discard silently and start a fresh round. A corrupt save never crashes, never shows an error, and never produces a board the engine would reject.

Android's CSV format has a subtlety worth knowing: it parses with `mapNotNull(String::toIntOrNull)`, which *drops* unparseable cells rather than failing. A grid of `"2,x,4"` would yield two values, not three. The length check immediately after is what converts that into a clean rejection instead of a short, misaligned board — and there is a test named for exactly that.

### State shape reference

The same conceptual state, expressed three ways. Field-for-field equivalence is what makes the contract checkable.

| Concept | Web (`state` object) | iOS (`GameViewModel`) | Android (`GameViewModel`) |
| --- | --- | --- | --- |
| Board | `board: number[16]` | `@Published var grid: [[Int]]` | `var grid by mutableStateOf` |
| Score | `score: number` | `@Published var score: Int` | `var score by mutableStateOf` |
| Best score | `best: number` | `@Published private(set) var highScore` | `var highScore by mutableStateOf` |
| Win flag | `won: boolean` | `@Published var hasWon: Bool` | `var hasWon by mutableStateOf` |
| Game over | `gameOver: boolean` | derived via `isGameOver()` | derived via `isGameOver()` |
| Undo slot | `history: Snapshot \| null` | `private var previous: Snapshot?` | `private var previous: Snapshot?` |
| Undo availability | `!!state.history` | `@Published private(set) var canUndo` | `var canUndo by mutableStateOf` |
| Touch origin | `touchStart: {x,y} \| null` | gesture-local | gesture-local |

Two deliberate differences:

- **Web keeps `gameOver` in state; the native clients derive it.** On the web the value is also part of the persisted payload's implied contract and is read by `render_game_to_text()`, so caching it avoids recomputing on every state dump. The natives recompute — it is O(16) with a short-circuit.
- **`canUndo` is explicit on the natives, derived on the web.** SwiftUI and Compose both need an observable property to drive a button's `disabled` state; the web reads `!!state.history` directly at render time.

The snapshot stored for undo is the same three fields everywhere: **board, score, win flag**. Not `best` — the best score is monotonic and must survive an undo. Not `gameOver` — it is recomputed from the restored board.

---

## Input pipeline

Every client accepts more than one input method, and all of them funnel into the same `move(direction)` call.

```mermaid
flowchart TB
    subgraph WebIn[Web]
        WK[keydown] --> WMap[keyMap lookup]
        WT[touchstart → touchend] --> WThr[28 px threshold]
        WB["buttons[data-direction]"] --> WD[dataset.direction]
        WMap --> WMove[move direction]
        WThr --> WMove
        WD --> WMove
    end

    subgraph IOSIn[iOS]
        IG["DragGesture minimumDistance 22"] --> IMove[swipe direction]
        IBtn[on-screen controls] --> IMove
    end

    subgraph DroidIn[Android]
        DG["detectDragGestures + 36 px threshold"] --> DMove[swipe direction]
        DBtn[on-screen controls] --> DMove
    end
```

### Key mapping (web)

| Keys | Direction |
| --- | --- |
| `ArrowUp` `w` `W` | up |
| `ArrowDown` `s` `S` | down |
| `ArrowLeft` `a` `A` | left |
| `ArrowRight` `d` `D` | right |
| `f` `F` | toggle fullscreen |

Both cases of each WASD letter are mapped explicitly rather than lowercasing the key, because `event.key` reports the shifted character and a player with Caps Lock on is still a player. `preventDefault()` fires only for a mapped movement key, so browser shortcuts and text input elsewhere are untouched. **Keys are ignored entirely while the new-game dialog is open** — the dialog owns the keyboard.

### Swipe resolution

All three clients resolve a swipe the same way: take the larger absolute component, then its sign.

```mermaid
flowchart TD
    End[Gesture ends] --> Start{Origin recorded?}
    Start -->|no| Ignore[Ignore]
    Start -->|yes| Delta["dx, dy from origin"]
    Delta --> Thresh{"max abs dx, abs dy ≥ threshold?"}
    Thresh -->|no| Ignore
    Thresh -->|yes| Axis{"abs dx &gt; abs dy?"}
    Axis -->|yes| Horiz{"dx &gt; 0?"}
    Axis -->|no| Vert{"dy &gt; 0?"}
    Horiz -->|yes| R[right]
    Horiz -->|no| L[left]
    Vert -->|yes| D[down]
    Vert -->|no| U[up]
```

The thresholds differ per platform, and that is correct rather than an inconsistency — the units are not the same thing:

| Client | Threshold | Unit |
| --- | --- | --- |
| Web | 28 | CSS pixels |
| iOS | 22 | points (`DragGesture.minimumDistance`) |
| Android | 36 | pixels, from Compose pointer input |

Each is tuned so a deliberate flick registers and an imprecise tap does not. A diagonal swipe resolves to its dominant axis rather than being rejected — asserted by a test, because rejecting diagonals makes the board feel unresponsive to anyone who does not swipe perfectly straight.

---

## Rendering pipelines

Three genuinely different rendering models, held to the same visual result.

```mermaid
flowchart TB
    subgraph W["Web — imperative, incremental"]
        W1[state changes] --> W2["render(animate)"]
        W2 --> W3{16 cells exist?}
        W3 -->|no| W4[build rows + cells once]
        W3 -->|yes| W5[reuse]
        W4 --> W5
        W5 --> W6["per cell: textContent · dataset.value<br/>aria-label · toggle 'pop'"]
        W6 --> W7[score · best · undo disabled]
    end

    subgraph I["iOS — declarative, diffed"]
        I1["@Published mutation"] --> I2[SwiftUI invalidates]
        I2 --> I3[body re-evaluated]
        I3 --> I4[framework diffs the tree]
    end

    subgraph A["Android — declarative, recomposed"]
        A1["mutableStateOf write"] --> A2[snapshot system notifies readers]
        A2 --> A3[only readers recompose]
    end
```

| | Web | iOS | Android |
| --- | --- | --- | --- |
| Model | Imperative DOM mutation | Declarative, framework-diffed | Declarative, snapshot-driven |
| Granularity | Explicit — the code names the 16 cells | Whole `body`, diffed by SwiftUI | Only composables that read the changed state |
| Animation trigger | `pop` class toggled per changed tile | `contentTransition` / implicit animations | `animateColorAsState` + spring scale |
| Cost of a mistake | Rebuilding cells destroys focus and animation | Over-broad `body` re-evaluates more than needed | Reading state too high recomposes too much |

The web's `pop` class is toggled with `Boolean(animate && value && value !== previous)` — it fires only for a cell whose value actually changed on an animated render. A redraw (`advanceTime()`) passes `animate: false`, so nothing re-animates. Both halves of that are tested.

### Design tokens, shared by hand

There is no shared stylesheet, yet the three clients render the same colours. The palette is duplicated deliberately and kept in step by review — and the values are **byte-identical**, not merely similar:

| Token | Web CSS | iOS `Color(red:green:blue:)` | Android `Color(…)` |
| --- | --- | --- | --- |
| Paper | `#f5f0e6` | `0.961, 0.941, 0.902` | `0xFFF5F0E6` |
| Ink | `#24231f` | `0.141, 0.137, 0.122` | `0xFF24231F` |
| Accent | `#e96345` | `0.914, 0.388, 0.271` | `0xFFE96345` |
| Muted | `#6f6a61` | `0.435, 0.416, 0.380` | `0xFF6F6A61` |
| Board | `#a99d8e` | `0.663, 0.616, 0.557` | `0xFFA99D8E` |
| Empty cell | `#bdb2a4` | `0.741, 0.698, 0.643` | `0xFFBDB2A4` |
| Tile ink | `#514b43` | `0.318, 0.294, 0.263` | `0xFF514B43` |

The tile ramp is likewise identical across all three:

| Tile | Colour | | Tile | Colour |
| --- | --- | --- | --- | --- |
| 2 | `#f1e8d9` | | 128 | `#d8ad5b` |
| 4 | `#eadbc1` | | 256 | `#c99a40` |
| 8 | `#efaa73` | | 512 | `#b27a32` |
| 16 | `#e98a5f` | | 1024 | `#735b49` |
| 32 | `#e56b51` | | 2048 | `#24231f` |
| 64 | `#d94c3f` | | 8192+ | `#171714` |

Text flips to white at 8 and above, on every client. The ramp is warm-neutral through 4, heats through the oranges and reds to 64, shifts to gold for the 128–512 band, then goes dark for 1024 and above — so a player reads their progress by temperature, not by reading the number.

**Changing a colour is a three-file edit.** This is the most common parity drift in the repository and the cheapest to catch: the values above are the reference.

### Motion architecture

| Element | Web | iOS | Android |
| --- | --- | --- | --- |
| Tile value change | `transition: background-color .18s ease, transform .18s ease` | implicit SwiftUI animation | `animateColorAsState` |
| New / merged tile | `@keyframes pop` — `scale(.82)` → `scale(1)` | scale transition | spring, 82% → 100% |
| Score change | — | `.contentTransition(.numericText())` | `AnimatedContent` |
| Overlay | `fade-in .25s ease` | transition | `tween(250)` |

The `.82 → 1` pop is the same figure on all three clients, and the 250 ms overlay fade matches between web and Android. These numbers were aligned on purpose: a tile that pops differently on Android than on the web is a parity bug even though no rule changed.

**Reduced motion is honoured everywhere.** The web collapses every animation and transition to `.01ms` under `prefers-reduced-motion: reduce`; Android swaps its `tween` for `snap()` when animations are disabled. Compose instrumentation tests additionally require animations disabled on the device — enabled animations are the most common cause of intermittent instrumentation failures, and they fail in ways that look like real defects.

---

## Web client

```mermaid
flowchart TB
    subgraph Page[index.html]
        Grid[#gridContainer]
        HUD[score · best · undo · new game]
        Msg[#gameMessage overlay]
        Status[#statusLine aria-live]
    end

    subgraph JS[Web-Version/]
        Engine[game-engine.js<br/>pure rules]
        Ctrl[script.js<br/>IIFE controller]
    end

    LS[(localStorage)]

    Ctrl --> Engine
    Ctrl --> Grid
    Ctrl --> HUD
    Ctrl --> Msg
    Ctrl --> Status
    Ctrl <--> LS

    Keys[keydown] --> Ctrl
    Touch[touchstart/move/end/cancel] --> Grid
    Buttons[data-direction buttons] --> Ctrl
    Grid --> Ctrl
```

Static files, no bundler, no transpiler, no runtime dependency. `script.js` is an IIFE that reads the document **once** on load and then talks to the page only through the elements it captured.

That property is not incidental — it is what makes the controller unit-testable. `tests/web/helpers/fake-dom.js` provides a hand-written stand-in for the document, so keyboard handling, touch handling, rendering, message states, and persistence are all covered by `node --test` with no browser at all.

```mermaid
flowchart LR
    Test[game-controller.test.js] --> Harness[fake-dom.js]
    Harness --> Elements[Fake elements<br/>capture listeners]
    Harness --> Storage[Fake localStorage]
    Harness --> Require["fresh require of script.js"]
    Require --> Controller[Controller instance]
    Test -->|key, swipe, click| Harness
    Harness -->|state via render_game_to_text| Test
```

**Keep the controller that way.** A controller that reaches back into `document` mid-flight is one that can only be tested in a real browser.

Rendering is incremental: the 16 cells are built once and then updated in place. A `pop` class is toggled only on tiles whose value actually changed this move, so a re-render does not re-animate a static board.

The controller exposes two hooks for testing and automation:

| Hook | Purpose |
| --- | --- |
| `window.render_game_to_text()` | A JSON dump of board, score, best, undo availability, mode, and available moves |
| `window.advanceTime()` | Forces a re-render without animation |

The Playwright suite drives real input events and reads state back through the first hook. Keep it accurate when the state shape changes, or the browser suite silently loses its assertions.

---

## PWA and discovery surface

The web client is an installable progressive web app and is the only client with a public surface to be discovered, so it carries metadata the other two do not need.

```mermaid
flowchart TB
    subgraph Install[Installability]
        Man[manifest.json]
        Man --> Ident["id · start_url · scope"]
        Man --> Disp["display: standalone<br/>display_override"]
        Man --> Theme["theme_color · background_color<br/>#f5f0e6"]
        Man --> Icons[icons]
        Man --> Cuts["shortcuts:<br/>new round · how to play"]
        Man --> Shots[screenshots]
    end

    subgraph Discover[Discoverability]
        Sitemap[sitemap.xml]
        Robots["robots.txt → sitemap directive"]
        LLMs[llms.txt]
        LD["JSON-LD (schema.org)"]
        Canon[canonical URLs]
        NF[404.html]
    end

    Validate[scripts/validate-repository.mjs] --> Man
    Validate --> Sitemap
    Validate --> Robots
    Validate --> LLMs
    Validate --> LD
    Validate --> Canon
```

Every one of those is validated by `make check`, so a broken manifest or a stale sitemap fails before it is committed rather than after it is deployed.

| Artefact | Purpose | Validated for |
| --- | --- | --- |
| `manifest.json` | Installability, icons, shortcuts, theme | Well-formed JSON; every referenced icon exists; screenshot dimensions match the actual PNG |
| `sitemap.xml` | Search indexing | Entries present and canonical |
| `robots.txt` | Crawler directives | Contains a `sitemap:` directive |
| `llms.txt` | Machine-readable project summary for LLM agents | Present and reachable |
| JSON-LD in `index.html` | schema.org structured data | Present |
| `404.html` | GitHub Pages fallback | Present |

The screenshot check is stricter than it looks and exists because of a real drift: the manifest declared `1440x1526` while the PNG on disk was `1440x1566`. The test now reads the actual dimensions out of the **PNG header** rather than trusting either the manifest or a hard-coded constant:

```javascript
const header = fs.readFileSync(file).subarray(16, 24);
const declared = `${header.readUInt32BE(0)}x${header.readUInt32BE(4)}`;
assert.equal(screenshot.sizes, declared, /* … */);
```

That is the general shape of every check in `validate-repository.mjs`: **compare the declaration against the artefact**, never against a second declaration that can drift alongside it.

There is no service worker. The app is static, small, and cached normally by the browser; offline play works from cache without one, and adding one would introduce an update-lifecycle problem the app does not otherwise have.

---

## iOS client

```mermaid
flowchart TB
    App[Game_2048App.swift] --> View[GameView.swift]
    View --> VM[GameViewModel<br/>ObservableObject]
    VM --> UD[(UserDefaults)]

    View -.@Published.-> Grid[grid]
    View -.@Published.-> Score[score]
    View -.@Published.-> Best[highScore]
    View -.@Published.-> Won[hasWon]
    View -.@Published.-> Undo[canUndo]
```

`GameViewModel` is an `ObservableObject` holding both the rules and the state. It takes three injected dependencies, all defaulted:

```swift
init(
    loadSavedGame: Bool = true,
    defaults: UserDefaults = .standard,
    randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) },
    randomUnit: @escaping () -> Double = { Double.random(in: 0..<1) }
)
```

**`loadSavedGame` is also the write switch.** A view model built with `false` is a throwaway (a SwiftUI preview, or a test that wants a clean board) and deliberately never persists. This surprised a test during development — a "persistence" test built that way saved nothing and proved nothing — so it is called out here and in the test file.

### Layout

`GameView` wraps its content in `ViewThatFits(in: .vertical)`. This is not cosmetic. An earlier version placed the board inside a `ScrollView`, and a `ScrollView`'s pan gesture always wins against a SwiftUI `DragGesture` — so **every vertical swipe scrolled the page instead of moving the board**.

```mermaid
flowchart TD
    Content[Board + HUD content] --> Fits{Fits vertically?}
    Fits -->|yes| Direct[Render directly — board owns the gesture]
    Fits -->|no| Scroll[Fall back to a scrolling layout]
```

Three changes were tried before the real cause was found, and the sequence is instructive:

| Attempt | Why it was not sufficient |
| --- | --- |
| `.highPriorityGesture` | Cannot beat a UIKit `UIPanGestureRecognizer` — priority is resolved inside UIKit, not SwiftUI. Still in place, and correct; it just was not the problem |
| `.scrollBounceBehavior(.basedOnSize)` | The content genuinely overflowed, so bouncing was not the problem either |
| `ViewThatFits` alone | Still selected the scrolling branch, because the content measured 887 pt in an 874 pt viewport |

The actual fix was trimming spacing so the content fits, which makes `ViewThatFits` select the non-scrolling branch and leaves the board owning its gesture. The board still declares `.highPriorityGesture(DragGesture(minimumDistance: 22))`.

**The lesson worth recording: three attempts producing byte-identical failures means the change is not reaching the behaviour at all.** That is a signal to stop and re-measure, not to try a fourth fix.

---

## Android client

```mermaid
flowchart TB
    Activity[MainActivity<br/>ComponentActivity] --> Compose[setContent]
    Compose --> Screen[Game screen composable]
    Screen --> VM[GameViewModel]
    VM --> Storage[GameStorage interface]
    Storage --> Prefs[SharedPreferencesGameStorage]
    Prefs --> SP[(SharedPreferences)]

    Screen -.mutableStateOf.-> Grid[grid]
    Screen -.mutableStateOf.-> Score[score]
    Screen -.mutableStateOf.-> Won[hasWon]
    Screen -.mutableStateOf.-> Undo[canUndo]
```

State is Compose `mutableStateOf`, so a write recomposes exactly the readers.

Storage is behind an interface — this is the one place any client abstracts its persistence, and it exists for testability:

```mermaid
classDiagram
    class GameStorage {
        <<interface>>
        +load() SavedGame?
        +loadBest() Int
        +save(game: SavedGame)
    }
    class SavedGame {
        grid: List~List~Int~~
        score: Int
        best: Int
        hasWon: Boolean
    }
    class SharedPreferencesGameStorage {
        -preferences: SharedPreferences
    }
    class MemoryStorage {
        <<test double>>
    }
    GameStorage <|.. SharedPreferencesGameStorage
    GameStorage <|.. MemoryStorage
    GameStorage ..> SavedGame
```

`GameViewModel` takes a nullable `GameStorage`, so the rules suite runs entirely in memory while a separate suite exercises the real `SharedPreferences` serialisation against a hand-written in-memory fake — no Robolectric, no mocking framework, no Android runtime.

---

## Gesture ownership

**A board swipe belongs to the board.** It must never scroll, bounce, or pan the surrounding screen, and every direction must register. Each client enforces this differently because each platform fights back differently.

```mermaid
flowchart TB
    subgraph W[Web]
        W1["board: touch-action: none"] --> W2["non-passive touchmove guard"]
        W2 --> W3["html/body: overscroll-behavior: none"]
        W3 --> W4[touchcancel clears the origin]
    end

    subgraph I[iOS]
        I1["ViewThatFits keeps the board<br/>out of any scrolling container"] --> I2["DragGesture, 22 pt minimum"]
    end

    subgraph A[Android]
        A1[detectDragGestures] --> A2["change.consume() on every pointer change"]
        A2 --> A3[Parent scroll never sees the gesture]
    end
```

Details that each exist because of a real bug:

- **Web — the `touchmove` listener must be non-passive.** A passive listener cannot call `preventDefault`, so registering it passively silently disables the entire guard. There is a test asserting the listener is registered non-passively, because this failure is invisible at review time.
- **Web — `touchcancel` must clear the start point.** A system swipe or an incoming call cancels the gesture; without clearing, the next swipe is measured from a stale origin and moves the wrong way.
- **Web — the guard is scoped to the board.** Page scrolling everywhere else must keep working, and a test asserts `touchmove` outside a board swipe is left alone.
- **Android — consume every pointer change.** Without `change.consume()`, the parent scroll container also processes the drag and the screen moves with the board.
- **iOS — a 22 pt minimum distance** keeps a tap from registering as a micro-swipe.

All three are covered by tests. See [`docs/testing.md`](docs/testing.md#gesture-ownership).

---

## Test strategy

```mermaid
flowchart TB
    UI["Browser / simulator / emulator<br/>real input, real rendering"]
    Unit["Deterministic unit suites<br/>rules, controller, storage"]

    UI --> Unit

    Unit --> W["Web: 65 tests<br/>engine + controller + assets"]
    Unit --> I["iOS: 49 tests<br/>model + persistence + edges"]
    Unit --> A["Android: 42 tests<br/>ViewModel + storage"]

    UI --> WB["Web: 8 Chromium flows"]
    UI --> IU["iOS: 9 XCUITest flows"]
    UI --> AU["Android: 5 Compose tests"]
```

The split is deliberate: **rules go in the deterministic suite on all three platforms, because parity is the point.** User-flow behaviour goes in the platform UI suite, asserting a user-visible outcome rather than re-deriving the rules.

| Platform | Deterministic | UI / integration | Runner |
| --- | --- | --- | --- |
| Web | 65 unit + 2 tooling | 8 Chromium scenarios | `node --test`, Playwright |
| iOS | 49 model tests | 9 XCUITest flows (10 executions) | XCTest |
| Android | 42 JVM tests | 5 Compose instrumentation tests | JUnit 4, Compose UI Test |

The iOS UI suite reports ten executions because the launch test runs once per appearance mode.

### Determinism seams

Every place a test can pin behaviour that would otherwise be random, timing-dependent, or environmental. **This table is the test strategy.** Without these seams, the suites could only assert that nothing threw.

| Non-determinism | Seam | Injected by |
| --- | --- | --- |
| Tile spawn location | `randomIndex` / first roll of `random()` | Web: `addRandomTile(board, random)`. iOS/Android: constructor closure |
| Tile spawn value (2 vs 4) | `randomUnit` / second roll | Same |
| Persisted state | Storage abstraction | Web: fake `localStorage`. iOS: `UserDefaults(suiteName:)`. Android: `GameStorage` interface |
| Whether persistence happens at all | iOS `loadSavedGame` flag | Constructor |
| The DOM | `tests/web/helpers/fake-dom.js` | Test harness |
| Simulator / emulator choice | `IOS_SIMULATOR_ID`, `scripts/common.sh` resolution | Environment |
| Coverage floor | `IOS_MINIMUM_COVERAGE` | Environment |

The rule that follows from the first two rows: **a valid move always spawns a tile.** Asserting a whole row after a move couples the assertion to where the injected generator put that tile. Assert the cells the merge produced, plus the score. Three tests broke on exactly this during development, which is why it is written down here, in [`docs/testing.md`](docs/testing.md), and in `.github/CONTRIBUTING.md`.

### The fake DOM harness

`tests/web/helpers/fake-dom.js` is the piece that makes 100 % web coverage achievable without a browser in the loop. It is worth understanding before writing a controller test.

```mermaid
flowchart TB
    Call["loadController({ storage, random })"] --> Build[Build fake elements by id]
    Build --> Hidden["gameMessage + messageSecondary start hidden<br/>(they carry 'hidden' in index.html)"]
    Hidden --> Install["run(): install window, document,<br/>localStorage, Math.random"]
    Install --> Fresh["delete require.cache → fresh require"]
    Fresh --> IIFE[script.js IIFE executes]
    IIFE --> Capture[Controller captures elements + registers listeners]
    Capture --> Wrap["Wrap every element.dispatch in run()"]
    Wrap --> Handle[Return handle]

    Handle --> API["key() · swipe() · dispatch()<br/>state() · board() · saved()"]
```

Four design points, each of which was a bug first:

1. **Globals are installed around *every* interaction, not just the load.** The controller keeps talking to `localStorage` and `document` long after it initialises. Restoring them afterwards is what keeps two loaded controllers independent within one test file.
2. **`require.cache` is cleared per load.** The controller is an IIFE; a fresh `require` is the only way to re-run it. Without this, every test would share one controller.
3. **`gameMessage` and `messageSecondary` start hidden**, because they carry the `hidden` attribute in `index.html`. Defaulting them visible made the very first render look like a finished game.
4. **Listener options are recorded**, so a test can assert that `touchmove` was registered *non-passively*. That is not observable any other way, and registering it passively silently disables the entire scroll guard.

The harness is not a general-purpose DOM. It implements what the controller actually calls and nothing more — `querySelectorAll` handles class selectors only, `getElementById` returns from a fixed map. **Keep it that way.** If the controller starts needing something the harness cannot express, that is usually a signal the controller is reaching too far into the page.

### Coverage gates

Every platform enforces a floor, and all three sit far above it.

| Platform | Gate | Current | Enforced by |
| --- | --- | --- | --- |
| Web | 100 % statements / lines / functions, 95 % branches, across all of `Web-Version/` | 100 % lines, 98.75 % branches | `c8`, in `npm run test:unit` |
| iOS | 90 % lines of the `Game-2048.app` target | 99.44 % | `xccov` in `scripts/test-ios.sh` and in CI |
| Android | 90 % lines, 85 % branches of the Kotlin engine and storage | 99.21 % lines, 91.26 % branches | JaCoCo `jacocoCoverageVerification` |

`MainActivity` sits outside the Android gate on purpose: it is Compose and is only reachable on a device, which `make test-android-device` covers. Holding the whole module to a JVM-only threshold would either fail on every machine without an emulator or push the number down to something meaningless.

**Lowering a threshold is never the fix for a failing gate.**

### Failure modes and how each is caught

The classes of defect this architecture is actually exposed to, and what stands between each one and a user.

| Failure mode | Symptom | Caught by |
| --- | --- | --- |
| Parity drift — a rule changes on one client only | The game behaves differently on Android | Three deterministic suites asserting the same contract; a CI job per platform |
| Merged tile merges again | `[2,2,4]` → `[8]` | A dedicated test on each platform, named for the rule |
| Merge order flips for a direction | `[2,2,2,0]` right gives `4 2` instead of `2 4` | Direction-specific ordering tests on each platform |
| Ineffective move spawns or scores | The board gains a tile from a blocked swipe | `swipe()` return value asserted `false`, plus board equality |
| Undo consumed by a blocked move | Player loses their undo without moving | `canUndo` asserted false after an ineffective swipe |
| Score leaks on a rejected move | Score creeps up from blocked swipes | Explicit test — `mergeLine` accumulates before the move is validated, so the rollback is load-bearing |
| Corrupt save crashes the app | White screen on launch | Six rejection-path tests per client: unparseable, wrong length, non-power-of-two, negative, non-numeric, negative score |
| Board swipe scrolls the page | Vertical swipes do nothing but move the screen | Gesture-ownership tests on all three; on web, an assertion that `touchmove` is non-passive |
| Stale touch origin after a cancelled gesture | Next swipe moves the wrong way | `touchcancel` test |
| DOM rebuilt per move | Focus lost, animations re-fire | Test asserting the same cell objects survive a move |
| Unlabelled cells | Board unusable with a screen reader | Test asserting every cell has `role` and an `aria-label` |
| Manifest drifts from its assets | Install prompt broken or wrong screenshot | `validate-repository.mjs` reads the PNG header |
| iOS test file not in the target | Test silently never runs | Documented; the count in `docs/testing.md` is the check |
| Toolchain assumption (`adb` on `PATH`, right `java`) | Works on the author's machine only | Every entry point routes through `scripts/`; the dev container proves a clean environment |

The two entries with no automated check — the iOS target membership and parity drift in *newly added* behaviour — are the ones that need human attention in review. Everything else fails a build.

---

## Build topology

Three build systems, no coordination between them. Each can be broken without blocking the other two.

```mermaid
flowchart TB
    subgraph WebB[Web — no build]
        WSrc["index.html · Web-Version/*"] --> WServe[Served as-is]
        WSrc --> WTest["node --test + c8"]
    end

    subgraph IOSB[iOS — Xcode]
        Proj["2048 Game.xcodeproj"] --> T1[Game-2048]
        Proj --> T2[Game-2048Tests]
        Proj --> T3[Game-2048UITests]
        T1 --> Sim[Simulator build, unsigned]
    end

    subgraph DroidB[Android — Gradle]
        Settings[settings.gradle.kts] --> Foojay["foojay-resolver-convention 0.9.0"]
        Daemon[gradle-daemon-jvm.properties] --> JDK["Adoptium JDK 17, auto-provisioned"]
        Foojay --> JDK
        JDK --> AGP["AGP · compileSdk 34 · minSdk 24"]
        AGP --> APK[Debug APK]
        AGP --> Jacoco[JaCoCo report + gate]
    end
```

| | Web | iOS | Android |
| --- | --- | --- | --- |
| Build system | none | Xcode / `xcodebuild` | Gradle 8.13, Kotlin DSL |
| Targets | — | app, unit tests, UI tests | app module |
| Platform floor | modern evergreen browsers | iOS 17.4 | minSdk 24, compileSdk / targetSdk 34 |
| Language level | ES2020, no transpile | Swift 6 | Kotlin, `jvmTarget` 1.8 |
| Signing | — | none, `CODE_SIGNING_ALLOWED=NO` | none, debug only |
| Toolchain needed | Node 22 | Xcode on macOS | Android SDK only — **no preinstalled JDK** |

Two things worth knowing before touching a build file:

- **The Xcode project has no synchronised file groups.** A new Swift test file must be added to the `Game-2048Tests` target in `project.pbxproj` — four entries: a `PBXBuildFile`, a `PBXFileReference`, a group child, and a `Sources` build-phase entry. A file that is merely on disk compiles never and runs never, silently.
- **There are two `.xcodeproj` directories.** `2048 Game.xcodeproj` is real; `Game-2048.xcodeproj` has no `project.pbxproj` and is a stray. Scripts name the former explicitly, which is why they work.

### The JDK-free Android path

Onboarding a new contributor was the design goal here, and it is worth spelling out because it is unusual:

```mermaid
sequenceDiagram
    participant Dev as Contributor
    participant Make as make test-android
    participant Script as scripts/android.sh
    participant Gradle as Gradle 8.13
    participant Foojay as api.foojay.io

    Dev->>Make: no JDK installed
    Make->>Script: resolve a JDK if one exists
    Note over Script: non-fatal if absent — emits a notice
    Script->>Gradle: ./gradlew testDebugUnitTest
    Gradle->>Gradle: read gradle-daemon-jvm.properties
    Note over Gradle: toolchainVendor=ADOPTIUM<br/>toolchainVersion=17
    Gradle->>Foojay: resolve a matching JDK for this OS + arch
    Foojay-->>Gradle: Adoptium 17
    Gradle->>Gradle: cache in ~/.gradle/jdks/
    Gradle-->>Dev: tests run
```

`gradle-daemon-jvm.properties` pins the vendor and version and carries a per-platform download URL for every OS/architecture pair, so the same committed file works on an Apple-silicon Mac, an x86 Linux CI runner, and Windows. The first invocation pays a one-time ~180 MB download; every one after is cached.

`scripts/android.sh` still tries to resolve a local JDK 17 first, and **must not hard-fail when there is none** — that was a real bug, where `set -e` plus a strict `use_java_17` broke the exact scenario this design exists to support.

### Dev container

`.devcontainer/` provides a Debian image with Java 17, the Android SDK, Node, and ShellCheck for contributors without a local toolchain.

```mermaid
flowchart LR
    DC[".devcontainer/Dockerfile<br/>devcontainers/java:1-17-bookworm"] --> SDK["Android SDK 34<br/>build-tools 34.0.0"]
    DC --> Node[Node + npm]
    DC --> Shell[ShellCheck]
    SDK --> Links["symlink adb · sdkmanager · avdmanager<br/>into /usr/local/bin"]
    Links --> Verify["make verify-devcontainer"]
    Verify --> Report["ok/fail per tool"]
```

The symlinks into `/usr/local/bin` are not redundant. The verification runs through a **login shell**, which sources `/etc/profile` and *resets* `PATH` — discarding anything set via `ENV PATH` in the Dockerfile. Putting the binaries on the default `PATH` is what makes them reachable either way. That is documented in the script itself so nobody "simplifies" it back.

The container covers the web and Android workflows. **iOS is not covered** and cannot be — it needs Xcode on a macOS host.

---

## Accessibility

Accessibility is a contract clause, not a polish pass.

| Requirement | Web | iOS | Android |
| --- | --- | --- | --- |
| Icons | SVG | SF Symbols | Material vector |
| Screen-reader board | `role="grid"` / `row` / `gridcell`, per-cell `aria-label` | Accessibility labels on tiles | Content descriptions |
| Live announcements | `#statusLine` with `aria-live` | — | — |
| Keyboard | Arrows, WASD, `F` for fullscreen | — | — |
| Focus | Visible focus, message panel takes focus when shown | — | — |
| Motion | Respects reduced-motion | Respects reduced-motion | Respects reduced-motion |

**Never use ASCII, emoji, or Unicode glyphs as button icons.** Icon artwork is centred by geometry and layout, with an accessible name on the enclosing control.

Every cell carries `aria-label` of either `Tile <value>` or `Empty cell`, asserted by a test — a grid that reads as a wall of unlabelled divs is unusable with a screen reader, and that regression is easy to introduce while optimising rendering.

---

## Command surface

Everything goes through `make`. The targets wrap scripts that resolve toolchains, so a fresh clone works without manual environment setup.

```mermaid
flowchart LR
    Make[make] --> Check[check<br/>syntax · repo · shell · SEO]
    Make --> Serve[serve<br/>localhost:8080]
    Make --> TW[test-web]
    Make --> TI[test-ios]
    Make --> TA[test-android]
    Make --> T[test<br/>everything this host supports]
    Make --> Run[ios-run · android-run]
    Make --> Shots[screenshots-web]

    TW --> Scripts[scripts/*.sh]
    TI --> Scripts
    TA --> Scripts
    Run --> Scripts
```

| Command | Does |
| --- | --- |
| `make help` | Lists every supported workflow |
| `make check` | Fast pre-commit checks — also what the Husky hook runs |
| `make serve` | Serves the web app at `http://localhost:8080` |
| `make test-web` | Syntax, repo validation, unit tests with coverage, tooling tests, Chromium flows |
| `make test-ios` | Unit and UI tests on a resolved simulator, then the coverage gate |
| `make test-android` | Unit tests, coverage gate, lint, debug APK |
| `make test-android-device` | Adds Compose tests on a connected device |
| `make test` | Every suite the current host can run |
| `make ios-run` / `android-run` | Build, install, launch |
| `make screenshots-web` | Deterministic desktop and mobile captures into `output/` |

### Toolchain resolution

**Never call `adb`, `xcrun`, or `./gradlew` bare from a script or Make target.** On a default Android Studio install `adb` is not on `PATH`, and the machine's default `java` is frequently the wrong version.

```mermaid
flowchart TD
    Target[make target] --> Script[scripts/*.sh]
    Script --> Common[scripts/common.sh]

    Common --> JDK["use_java_17<br/>resolve a JDK 17"]
    Common --> ADB["resolve_adb<br/>ANDROID_HOME fallback"]
    Common --> Sim["resolve_ios_simulator<br/>+ boot_ios_simulator"]
    Common --> Guard["require_macos · require_command"]
```

The Android build additionally commits Gradle daemon JVM criteria in `Android-Version/Game2048/gradle/gradle-daemon-jvm.properties`, so **Gradle downloads and runs on a matching Adoptium JDK 17 regardless of the machine's default `java`**. The JVM suite therefore needs only the Android SDK — not a preinstalled JDK. The first invocation pays a one-time download into `~/.gradle/jdks/`.

A dev container covers the web and Android workflows for contributors without a local toolchain; `make verify-devcontainer` builds it and checks every tool. iOS is not covered there — it requires Xcode on a macOS host.

---

## CI topology

```mermaid
flowchart LR
    Push[push / PR / dispatch] --> Web[web · ubuntu]
    Push --> IOS[ios · macos-15]
    Push --> AJ[android-jvm · ubuntu]
    Push --> DK[docker · ubuntu]
    Push --> DA[docker-android · ubuntu]
    AJ --> AD[android-device · ubuntu]

    DA --> A1[SDK image · amd64 only]
    DA --> A2[verify toolchain in a login shell]
    DA --> A3[build APK + unit tests in the image]
    DA --> A4[publish to GHCR on a branch push]

    DK --> D1[build amd64 + arm64]
    DK --> D2[smoke test a running container]
    DK --> D3{"branch push?"}
    D3 -- yes --> D4[publish to GHCR]
    D3 -- "no, pull request" --> D5[build only, never publish]

    Web --> W1[npm audit]
    Web --> W2[syntax · repo · SEO validation]
    Web --> W3[ShellCheck]
    Web --> W4[unit tests + coverage gate]
    Web --> W5[Chromium flows]

    IOS --> I1[build-for-testing]
    IOS --> I2[model tests + coverage]
    IOS --> I3[UI + accessibility flows]
    IOS --> I4[coverage gate via xccov]

    AJ --> A1[unit tests]
    AJ --> A2[JaCoCo gate]
    AJ --> A3[lint]
    AJ --> A4[debug APK]

    AD --> D1[emulator Compose flows]
```

Four independently visible jobs, so a failure points straight at the responsible platform. Coverage reports, `.xcresult` bundles, Android reports, and the debug APK upload as artifacts **including on failure** — which is usually when they are needed.

ShellCheck is optional locally but **required in CI**. Install it (`brew install shellcheck`) to catch shell issues before pushing rather than after.

---

## Extending across three clients

Any behaviour change that touches the rules is three edits and three test edits. This is the workflow.

```mermaid
flowchart TD
    Start[Behaviour change] --> Kind{Touches the rules?}
    Kind -->|no, one platform's UI| Single["Change that client<br/>+ its UI test"]
    Kind -->|yes| Contract[Update the contract in ARCHITECTURE.md and AGENTS.md]

    Contract --> W[Web: engine or controller + test]
    Contract --> I[iOS: GameViewModel + XCTest]
    Contract --> A[Android: GameViewModel + JUnit]

    W --> WT[make test-web]
    I --> IT[make test-ios]
    A --> AT[make test-android]

    WT --> All{All three green?}
    IT --> All
    AT --> All
    All -->|no| Fix[Fix the divergence]
    Fix --> All
    All -->|yes| Docs[Update docs and README counts]
    Docs --> Shots{UI changed?}
    Shots -->|yes| Screens[Capture screenshots, inspect manually]
    Shots -->|no| Done[Done]
    Screens --> Done
```

Worked example — **adding a 4096 tile colour**:

| Step | File |
| --- | --- |
| 1. Web | `Web-Version/style.css` — add `[data-value="4096"]` |
| 2. iOS | `Game-2048/GameView.swift` — add a `case 4096` to `tileColor` |
| 3. Android | `…/ui/theme/Color.kt` — add `Tile4096`, wire it into the tile composable |
| 4. Verify | Compare against the [design-token table](#design-tokens-shared-by-hand); the hex must match exactly |
| 5. Screenshot | `make screenshots-web`, inspect manually |

No test changes — the ramp is presentation. Contrast that with **changing the spawn probability**, which touches the rules: three engine edits, three boundary tests updated (the exclusive `< 0.9` assertion on each platform), and this document's [spawning section](#tile-spawning-and-determinism).

Rules of thumb:

- **A rules change with a test on only one platform is incomplete**, even if the other two happen to already pass.
- **Prefer reaching a target board through injected state** over a long scripted move sequence — the test then says what it means.
- **Name the test after the behaviour it protects**, not the function it calls. The name is what a future maintainer reads when it fails at 2 a.m.
- **Confirm the test fails before your fix and passes after.** A test that never failed has proven nothing.

The [`2048-cross-platform-parity`](.agents/skills/2048-cross-platform-parity/SKILL.md) skill encodes this workflow for agents.

---

## Security and privacy posture

The threat model is short because the attack surface is small — and keeping it small is itself the design.

```mermaid
flowchart LR
    subgraph Device[The player's device]
        App[Game]
        Store[(localStorage / UserDefaults / SharedPreferences)]
        App <--> Store
    end

    Net((Network))
    App -. "no requests, ever" .- Net

    subgraph Supply[Supply chain]
        Dep["devDependencies only:<br/>c8 · husky · playwright"]
        Audit[npm audit in CI]
        Dep --> Audit
    end
```

| Property | Status |
| --- | --- |
| Data collected | None. No accounts, no analytics, no telemetry, no identifiers |
| Network calls at runtime | None on any client |
| Runtime dependencies | **Zero** on all three clients. The web app ships no third-party JavaScript |
| Build dependencies | Web: three devDependencies (`c8`, `husky`, `playwright`). Android: AndroidX and Compose. iOS: Apple SDKs only |
| Persisted data | One saved round and one best score, in platform-local storage. Never leaves the device |
| Untrusted input | Only the saved state, which is fully validated before use |
| Secrets in the repository | None. `local.properties`, keystores, signing material, and tokens are gitignored and never committed |
| Signing in CI | None. All builds are unsigned |
| Dependency monitoring | `npm audit` on every CI run. Upgrades are applied manually; no update bot is enabled |

The only place the app consumes data it did not create is the saved round, and every rejection path there is tested. There is no user-generated content, no URL parameter handling, no `eval`, no `innerHTML` with dynamic content — the DOM is built with `createElement` and `textContent`, so there is no injection sink to defend.

---

## Server-driven surfaces

The game is never server-driven. Rules, board, scoring, and undo are code, and
no payload can reach them. What *is* describable by data is **content** — the
help sheet today — the parts you would otherwise ship a build to change.

This exists because store review is slow. A typo in the help copy should not
wait days. It is built now rather than later because the expensive part is not
the transport, it is the contract and the fallback semantics, and designing
those under release pressure is how a bad contract ships.

**Today there is no server.** The only source is the app bundle, and neither
client makes a network request. See [Security and privacy](#security-and-privacy-posture).

```mermaid
flowchart TB
    Source["SurfaceSource<br/>(bundled today)"] --> Resolve[SurfaceResolver]
    Resolve --> Compat{Compatible?}
    Compat -->|"schema too new"| FB[Native fallback]
    Compat -->|"app too old"| FB
    Compat -->|"empty"| FB
    Compat -->|yes| Prune[Prune unrenderable nodes]
    Prune --> Any{Any left?}
    Any -->|no| FB
    Any -->|yes| Render[Render with the app's design system]
    Prune --> Problems[Report problems as diagnostics]
```

### The contract

| Piece | Rule |
| --- | --- |
| `Surface` | A versioned tree of typed nodes, with an optional `minimumAppVersion` gate |
| `SurfaceNode` | `id`, `type`, `properties`, `children`, optional `action` |
| Node types | Open, not an enum — a build that has never heard of a type must still *parse* the payload and skip that node |
| Properties | A closed union of string, number, boolean, list. Never `Any` |
| Actions | **Names**, resolved by the host against a handler map. A payload can ask for `newGame`; it cannot describe how to start one |
| Styling | Owned entirely by the renderer. A payload supplies content and order, never colours, fonts, or spacing |

### Why it cannot break a screen

Every failure mode ends at the app's own hand-written UI:

| Failure | Result |
| --- | --- |
| No payload published | Native fallback |
| Payload will not decode | Native fallback |
| `schemaVersion` newer than the build | Native fallback, whole surface refused |
| `minimumAppVersion` newer than the app | Native fallback, whole surface refused |
| Every node unknown | Native fallback |
| *Some* nodes unknown or missing a required property | Those nodes are pruned; siblings render |
| Action with no registered handler | Renders, control disabled, problem reported |

Deleting every published payload returns both apps to exactly the UI they ship
with — which is what makes the feature additive rather than load-bearing.

### Adding a remote publisher later

One new `SurfaceSource` and one line in the catalog. The renderer, validator,
resolver, and every test stay untouched. The *code* cost is small; the cost that
matters is the rest:

- Android gains an `INTERNET` permission, visible on the store listing.
- The privacy disclosure changes.
- A cache and staleness policy becomes necessary.
- The payload becomes an untrusted remote input, not just an untrusted local one.

That is a product decision, not a refactor, which is exactly why the seam exists
and the transport does not.

### Where it lives

| | iOS | Android |
| --- | --- | --- |
| Model + decode | `Game-2048/SDUI/Surface.swift` | `sdui/Surface.kt` |
| Validate + resolve | `Game-2048/SDUI/SurfaceResolver.swift` | `sdui/SurfaceResolver.kt` |
| Render | `Game-2048/SDUI/SurfaceView.swift` | rendered by the Compose help sheet |
| Wiring | `Game-2048/SDUI/SurfaceCatalog.swift` | `sdui/SurfaceCatalog.kt` |
| Payload | `Game-2048/Surfaces/help.json` | `assets/surfaces/help.json` |

Both payloads are byte-identical and a test asserts they stay that way, for the
same reason the [design tokens](#design-tokens-shared-by-hand) are checked: two
clients drifting apart is the failure mode this repository is built to prevent.

---

## Architectural invariants

These hold across all three clients. A change that breaks one is a bug regardless of what it enables.

**Rules**

- A valid move compacts tiles, merges equal neighbours **once**, scores the merged values, and spawns exactly one `2` or `4`.
- An ineffective move changes nothing, creates no undo snapshot, spawns no tile, and does not alter the score.
- Merging resolves from the destination edge inward, in every direction.
- Undo restores exactly the board, score, and win state before the most recent valid move, and is exactly one step deep.
- Reaching 2048 presents a win state and allows continued play.
- Game over requires a full board **and** no orthogonal equal pair.

**State**

- New game preserves the best score and requires confirmation when a round is in progress.
- The best score never decreases.
- Corrupt or structurally invalid saved state is discarded safely — never crashes, never partially restores.
- Game state stays on the device. No backend, analytics, accounts, remote storage, or network calls.

**Code**

- Source stays deterministic where tests inject a random tile provider.
- The web engine is side-effect free and does not mutate its inputs.
- The web controller reads the document once and thereafter only through captured elements.
- Rules logic on iOS and Android stays free of view dependencies.
- A board swipe never scrolls, bounces, or pans the surrounding screen.
- Icons are SVG, SF Symbols, or Material vectors — never ASCII, emoji, or Unicode glyphs.
- A server-driven surface describes **content only**, never rules, styling, or behaviour.
- Every surface has a native fallback, so no payload can blank or crash a screen.
- Surface actions are names resolved by the host, never code carried in data.
- Generated Xcode identifiers and Gradle wrapper binaries are not hand-edited.
- `local.properties`, signing material, tokens, build output, and local simulator data are never committed.

---

## Glossary

The vocabulary used consistently across the three clients, the tests, and this document. Using a different word for one of these in code is a review comment.

| Term | Means |
| --- | --- |
| **Board** | The 4×4 playfield. Flat 16-element array on the web, nested rows on the natives |
| **Tile** | One non-zero cell value. Always zero or a power of two |
| **Cell** | One position on the board, whether or not it holds a tile |
| **Line** | One row or column, extracted for merging. Always length 4 |
| **Compaction** | Removing gaps by sliding tiles toward the destination edge. Always precedes merging |
| **Merge** | Two equal adjacent tiles combining into their sum. Each tile merges at most once per move |
| **Gained** | The score a single move produced — the sum of tiles *created* by merging, not of tiles that moved |
| **Move** | One swipe or key press in a direction |
| **Valid move** | A move that changes the board. Scores, spawns, and creates an undo snapshot |
| **Ineffective move** | A move that changes nothing. Scores nothing, spawns nothing, creates no snapshot, and is not undoable |
| **Spawn** | The single new `2` or `4` placed after a valid move |
| **Snapshot** | The board, score, and win flag captured before a valid move, for undo. Exactly one is retained |
| **Best score** | The highest score achieved across rounds. Monotonic — survives new games and undo |
| **Win state** | Reaching 2048. Sticky, announced once, and does not end the round |
| **Game over** | A full board with no orthogonal equal pair |
| **Round** | One game from a fresh board to a new game or game over |
| **Determinism seam** | An injection point that lets a test pin otherwise-random behaviour |
| **Parity** | The three clients behaving identically for the same inputs |
| **Contract** | The list of behaviours every client must satisfy — see [Three clients, one contract](#three-clients-one-contract) |

## Further reading

- [`docs/architecture.md`](docs/architecture.md) — per-client implementation detail
- [`docs/testing.md`](docs/testing.md) — suite placement, gates, and diagnosing flaky device runs
- [`.github/README.md`](.github/README.md) — product overview, features, and screenshots
- [`AGENTS.md`](AGENTS.md) — the source of truth for coding agents
- [`.agents/skills/`](.agents/skills/) — per-area workflows, including cross-platform parity
- [`.github/CONTRIBUTING.md`](.github/CONTRIBUTING.md) — contribution and testing requirements
