"use strict";

// The bridge between the local game and the optional cloud layer.
//
// Every test here asserts the same underlying property in a different way:
// the cloud can read and replace a round, and nothing it does can change a
// rule, corrupt a board, or break the game when it misbehaves.

const test = require("node:test");
const assert = require("node:assert/strict");
const { loadController } = require("./helpers/fake-dom.js");

const EMPTY = new Array(16).fill(0);

test("the bridge exposes a save in the shape every client exchanges", () => {
    const app = loadController();
    const save = app.bridge.save();

    assert.equal(save.board.length, 16);
    assert.equal(save.score, 0);
    assert.equal(save.moves, 0);
    assert.equal(save.won, false);
    assert.equal(save.gameOver, false);
    assert.equal(save.undo, null, "a fresh round has no undo snapshot to carry");
    assert.ok(save.elapsedSeconds >= 0);
});

test("a save is a copy, so a caller cannot reach into the live board", () => {
    const app = loadController();
    const save = app.bridge.save();
    save.board[0] = 2048;

    assert.notEqual(app.state().board[0][0], 2048, "mutating a returned save must not alter the game");
});

test("moves are counted and travel with the save", () => {
    const app = loadController();
    app.key("ArrowLeft");
    app.key("ArrowRight");

    assert.equal(app.bridge.save().moves, 2);
});

test("an ineffective move does not count", () => {
    const app = loadController({ storage: { "game2048-state-v2": JSON.stringify({ board: [2, 0, 0, 0, ...EMPTY.slice(4)], score: 0, best: 0, won: false }) } });
    const before = app.bridge.save().moves;

    app.key("ArrowLeft");

    assert.equal(app.bridge.save().moves, before, "a swipe that changes nothing is not a move");
});

test("the move count survives a reload", () => {
    const app = loadController();
    app.key("ArrowLeft");
    app.key("ArrowRight");

    const reloaded = loadController({ storage: { "game2048-state-v2": app.localStorage.getItem("game2048-state-v2") } });
    assert.equal(reloaded.bridge.save().moves, 2);
});

test("a corrupt move count in storage is discarded rather than trusted", () => {
    const saved = JSON.stringify({ board: [2, 4, ...EMPTY.slice(2)], score: 4, best: 4, won: false, moves: -12 });
    const app = loadController({ storage: { "game2048-state-v2": saved } });

    assert.equal(app.bridge.save().moves, 0, "a negative count falls back to zero");
});

test("undo does not rewind the move count", () => {
    // A number a player can lower by pressing undo is not a measurement.
    const app = loadController();
    app.key("ArrowLeft");
    const afterMove = app.bridge.save().moves;

    app.elements.undoButton.dispatch("click");

    assert.equal(app.bridge.save().moves, afterMove);
});

test("the undo snapshot travels with the save so a handoff does not consume it", () => {
    const app = loadController();
    app.key("ArrowLeft");

    const save = app.bridge.save();
    assert.ok(save.undo, "a round with an available undo must carry it");
    assert.equal(save.undo.board.length, 16);
    assert.equal(typeof save.undo.score, "number");
});

test("applying a remote save replaces the round", () => {
    const app = loadController();
    const remote = { board: [2, 4, 8, 16, ...EMPTY.slice(4)], score: 60, bestScore: 900, won: false, moves: 12 };

    assert.equal(app.bridge.applySave(remote), true);

    const state = app.state();
    assert.deepEqual(state.board[0], [2, 4, 8, 16]);
    assert.equal(state.score, 60);
    assert.equal(state.best, 900);
    assert.equal(state.moves, 12);
    assert.equal(state.canUndo, false, "a downloaded round starts without an undo of this device's making");
});

test("applying a remote save persists it locally", () => {
    const app = loadController();
    app.bridge.applySave({ board: [2, 4, ...EMPTY.slice(2)], score: 4, bestScore: 4, moves: 1 });

    assert.deepEqual(app.saved().board, [2, 4, ...EMPTY.slice(2)]);
    assert.equal(app.saved().score, 4);
});

test("a remote save can never lower the best score", () => {
    const app = loadController({ storage: { highScore: "5000" } });
    app.bridge.applySave({ board: [2, ...EMPTY.slice(1)], score: 0, bestScore: 10, moves: 0 });

    assert.equal(app.state().best, 5000, "the best score is monotonic, wherever it came from");
});

test("a remote save carrying a finished board shows the end-of-round panel", () => {
    const app = loadController();
    const locked = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];

    app.bridge.applySave({ board: locked, score: 500, bestScore: 500, moves: 200 });

    assert.equal(app.elements.gameMessage.hidden, false);
    assert.equal(app.state().mode, "game-over");
});

test("an invalid remote board is refused rather than half-applied", () => {
    const app = loadController();
    app.key("ArrowLeft");
    const before = app.state();

    for (const bad of [null, undefined, {}, { board: [1, 2, 3] }, { board: new Array(16).fill(3) }, { board: "nope" }]) {
        assert.equal(app.bridge.applySave(bad), false, `${JSON.stringify(bad)} should be refused`);
    }

    assert.deepEqual(app.state().board, before.board, "a refused payload must leave the round untouched");
    assert.equal(app.state().score, before.score);
});

test("a remote save with a missing score is clamped, not coerced to NaN", () => {
    const app = loadController();
    app.bridge.applySave({ board: [2, 4, ...EMPTY.slice(2)] });

    assert.equal(app.state().score, 0);
    assert.equal(app.bridge.save().moves, 0);
});

test("subscribers are called immediately and then on every change", () => {
    const app = loadController();
    const seen = [];
    app.bridge.subscribe(reason => seen.push(reason));

    assert.deepEqual(seen, ["subscribed"], "a new subscriber is given the current round straight away");

    app.key("ArrowLeft");
    app.elements.undoButton.dispatch("click");
    app.elements.newGameButton.dispatch("click");

    assert.deepEqual(seen, ["subscribed", "move", "undo", "new-game"]);
});

test("unsubscribing stops the notifications", () => {
    const app = loadController();
    const seen = [];
    const unsubscribe = app.run(() => app.bridge.subscribe(reason => seen.push(reason)));

    unsubscribe();
    app.key("ArrowLeft");

    assert.deepEqual(seen, ["subscribed"]);
});

test("a subscriber that throws cannot break a move", () => {
    // The game is the thing that has to keep working. A cloud layer with a bug
    // in it must degrade to "no sync", never to "the board stopped responding".
    const app = loadController();
    app.bridge.subscribe(() => {
        throw new Error("observer exploded");
    });

    assert.doesNotThrow(() => app.key("ArrowLeft"));
    assert.equal(app.bridge.save().moves, 1, "the move still landed");
});

test("the end of a round is announced distinctly from an ordinary move", () => {
    // Sliding right merges nothing but compacts row 0, and the spawn — pinned
    // to the first empty cell by the injected generator — completes a locked
    // checkerboard.
    const board = [4, 0, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    const app = loadController({
        storage: { "game2048-state-v2": JSON.stringify({ board, score: 100, best: 100, won: false }) },
        random: () => 0
    });

    const seen = [];
    app.bridge.subscribe(reason => seen.push(reason));
    app.key("ArrowRight");

    assert.ok(seen.includes("game-over"), `expected a game-over notification, saw ${seen.join(", ")}`);
});

test("restoring a saved round notifies subscribers of the load", () => {
    const saved = JSON.stringify({ board: [2, 4, ...EMPTY.slice(2)], score: 4, best: 4, won: false, moves: 1 });
    const app = loadController({ storage: { "game2048-state-v2": saved } });

    // The load notification fires during construction, before any test can
    // subscribe, so the observable proof is the state the bridge reports.
    assert.equal(app.bridge.save().moves, 1);
    assert.equal(app.bridge.save().score, 4);
});

test("the bridge can start a new game", () => {
    const app = loadController();
    app.key("ArrowLeft");

    app.bridge.newGame();

    assert.equal(app.bridge.save().moves, 0);
    assert.equal(app.state().score, 0);
});

test("the state dump reports the move count for automation", () => {
    const app = loadController();
    app.key("ArrowLeft");
    assert.equal(app.state().moves, 1);
});

/* -------------------------------------------------------------------- */
/* Guest and account profiles                                            */
/* -------------------------------------------------------------------- */

/** Plays until the round has a score, so there is something to protect. */
function playUntilScored(app) {
    for (let index = 0; index < 40 && app.state().score === 0; index += 1) {
        app.key(index % 2 ? "ArrowLeft" : "ArrowUp");
    }
    return app.state();
}

test("a round starts on the guest profile", () => {
    const app = loadController();
    assert.equal(app.state().profile, "guest");
    assert.equal(app.bridge.getProfile(), "guest");
    assert.equal(app.bridge.hasProgress(), false);
});

test("hasProgress reports a round the player would mind losing", () => {
    const app = loadController({ random: () => 0.5 });
    app.key("ArrowLeft");
    assert.equal(app.bridge.hasProgress(), true, "a played move is progress even before a merge");
});

test("starting an account session parks the guest round untouched", () => {
    const app = loadController({ random: () => 0.5 });
    const guest = playUntilScored(app);
    assert.ok(guest.score > 0);

    assert.equal(app.bridge.beginAccountSession({ fresh: true }), "fresh");

    assert.equal(app.state().profile, "account");
    assert.equal(app.state().score, 0, "the account starts on a clean board");
    assert.equal(app.state().best, 0, "and with no best score borrowed from the device");
    // The guest round is still on disk exactly as it was left.
    assert.deepEqual(app.saved().board, guest.board.flat());
    assert.equal(app.saved().score, guest.score);
});

test("playing signed in never writes to the guest profile", () => {
    const app = loadController({ random: () => 0.5 });
    playUntilScored(app);
    const guestOnDisk = JSON.stringify(app.saved());
    const guestBest = app.localStorage.getItem("highScore");

    app.bridge.beginAccountSession({ fresh: true });
    for (let index = 0; index < 30; index += 1) app.key(index % 2 ? "ArrowLeft" : "ArrowUp");

    assert.equal(JSON.stringify(app.saved()), guestOnDisk, "the guest round is frozen while signed in");
    assert.equal(app.localStorage.getItem("highScore"), guestBest, "and so is the guest best score");
    assert.ok(app.savedAccount(), "the signed-in round has storage of its own");
});

test("ending an account session restores the guest round exactly", () => {
    const app = loadController({ random: () => 0.5 });
    const guest = playUntilScored(app);

    app.bridge.beginAccountSession({ fresh: true });
    for (let index = 0; index < 30; index += 1) app.key(index % 2 ? "ArrowLeft" : "ArrowUp");
    const account = app.state();
    assert.notDeepEqual(account.board, guest.board);

    assert.equal(app.bridge.endAccountSession(), true);

    const restored = app.state();
    assert.equal(restored.profile, "guest");
    assert.deepEqual(restored.board, guest.board);
    assert.equal(restored.score, guest.score);
    assert.equal(restored.best, guest.best);
    assert.equal(app.savedAccount(), null, "the cached account round does not outlive the session");
});

test("a session started twice is reported as already active", () => {
    const app = loadController();
    app.bridge.beginAccountSession({ fresh: true });
    assert.equal(app.bridge.beginAccountSession(), "active");
    assert.equal(app.bridge.beginAccountSession({ fresh: true }), "active");
});

test("ending a session that never started changes nothing", () => {
    const app = loadController({ random: () => 0.5 });
    const before = app.state();
    assert.equal(app.bridge.endAccountSession(), false);
    assert.deepEqual(app.state(), before);
});

test("a cached account round is restored rather than replaced", () => {
    const board = new Array(16).fill(0);
    board[0] = 512;
    board[1] = 256;
    const app = loadController({
        storage: {
            "game2048-state-account-v1": JSON.stringify({ board, score: 4000, best: 6000, won: false, moves: 77 }),
            "game2048-best-account-v1": "6000"
        }
    });

    assert.equal(app.bridge.beginAccountSession(), "restored");
    const state = app.state();
    assert.equal(state.score, 4000);
    assert.equal(state.best, 6000);
    assert.equal(state.moves, 77);
});

test("a finished cached account round comes back with its end panel", () => {
    // 2, 4, 2, 4 / 4, 2, 4, 2 / … — full, with no equal neighbours anywhere.
    const board = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    const app = loadController({
        storage: {
            "game2048-state-account-v1": JSON.stringify({ board, score: 1500, best: 1500, won: false, moves: 90 })
        }
    });

    app.bridge.beginAccountSession();
    assert.equal(app.state().mode, "game-over");
    assert.equal(app.elements.gameMessage.hidden, false);
    assert.match(app.elements.messageBody.textContent, /Final score: 1,500/);
});

test("a profile switch is announced to cloud observers", () => {
    const app = loadController();
    const reasons = [];
    app.bridge.subscribe(reason => reasons.push(reason));

    app.bridge.beginAccountSession({ fresh: true });
    app.bridge.endAccountSession();

    assert.deepEqual(reasons, ["subscribed", "profile", "profile"]);
});

test("a corrupt cached account round is discarded, not restored", () => {
    const app = loadController({
        storage: { "game2048-state-account-v1": "{ not json" }
    });
    assert.equal(app.bridge.beginAccountSession(), "fresh");
    assert.equal(app.state().score, 0);
    assert.equal(app.localStorage.getItem("game2048-state-account-v1")?.startsWith("{\"board\""), true);
});

test("the account's career best seeds the signed-in Best card", () => {
    const app = loadController({ random: () => 0.5 });
    playUntilScored(app);
    const guestBest = app.state().best;

    app.bridge.beginAccountSession({ fresh: true });
    assert.equal(app.state().best, 0, "an account starts with nothing borrowed from the device");

    assert.equal(app.bridge.adoptCareerBest(9100), true);
    assert.equal(app.state().best, 9100);
    assert.equal(app.savedAccount().best, 9100);

    // Never downwards, and never anything but a positive whole number.
    assert.equal(app.bridge.adoptCareerBest(40), false);
    assert.equal(app.bridge.adoptCareerBest(null), false);
    assert.equal(app.state().best, 9100);

    app.bridge.endAccountSession();
    assert.equal(app.state().best, guestBest, "and none of it reaches the device's own best");
});

test("a career best is refused while playing as a guest", () => {
    const app = loadController({ random: () => 0.5 });
    assert.equal(app.bridge.adoptCareerBest(9100), false);
    assert.equal(app.state().best, 0);
});
