import assert from "node:assert/strict";
import test from "node:test";
import { compareProgress, normalizeIncoming, progressOf } from "../../src/services/sync.js";

const BOARD = [2, 4, 8, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
const GRID = [[2, 4, 8, 16], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]];

test("a payload from the web client normalises", () => {
    const save = normalizeIncoming({ board: BOARD, score: 120, best: 900, moves: 14, client: "web" });
    assert.deepEqual(save.board, BOARD);
    assert.equal(save.score, 120);
    assert.equal(save.bestScore, 900, "`best` is the web client's field name and must be accepted");
    assert.equal(save.highestTile, 16, "the highest tile is derived, never trusted from the payload");
});

test("a payload from a native client sends rows and normalises to the same save", () => {
    const fromWeb = normalizeIncoming({ board: BOARD, score: 120 });
    const fromNative = normalizeIncoming({ grid: GRID, score: 120 });
    assert.deepEqual(fromNative.board, fromWeb.board, "both clients must reach identical stored state");
});

test("won and gameOver are derived when the client omits them", () => {
    const winning = normalizeIncoming({ board: [2048, ...new Array(15).fill(0)], score: 20_000 });
    assert.equal(winning.won, true);
    assert.equal(winning.gameOver, false, "a board with space is never over");

    const locked = normalizeIncoming({ board: [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2], score: 500 });
    assert.equal(locked.gameOver, true);
});

test("negative and fractional values are clamped rather than stored", () => {
    const save = normalizeIncoming({ board: BOARD, score: -50, moves: 3.9, elapsedSeconds: -1 });
    assert.equal(save.score, 0);
    assert.equal(save.moves, 3);
    assert.equal(save.elapsedSeconds, 0);
});

test("an invalid board is refused, not coerced", () => {
    assert.throws(() => normalizeIncoming({ board: [1, 2, 3], score: 0 }), /16 flat cells or a 4x4 grid/);
    assert.throws(() => normalizeIncoming({ score: 0 }), /16 flat cells or a 4x4 grid/);
});

test("an invalid undo snapshot is refused rather than silently dropped", () => {
    // Dropping it would consume the player's undo without telling anyone.
    assert.throws(
        () => normalizeIncoming({ board: BOARD, score: 10, undo: { board: [3, 3], score: 0 } }),
        /undo snapshot board is not a valid board/
    );
});

test("a valid undo snapshot travels with the save", () => {
    const save = normalizeIncoming({ board: BOARD, score: 40, undo: { board: GRID, score: 20, won: false } });
    assert.deepEqual(save.undoBoard, BOARD);
    assert.equal(save.undoScore, 20);
    assert.equal(save.undoWon, false);
});

test("progress compares by score, then moves, then revision", () => {
    assert.equal(compareProgress({ score: 200, moves: 1 }, { score: 100, moves: 99 }), 1, "score dominates");
    assert.equal(compareProgress({ score: 100, moves: 50 }, { score: 100, moves: 20 }), 1, "moves break a score tie");
    assert.equal(compareProgress({ score: 100, moves: 20, revision: 5 }, { score: 100, moves: 20, revision: 2 }), 1, "revision is the last resort");
    assert.equal(compareProgress({ score: 100, moves: 20, revision: 1 }, { score: 100, moves: 20, revision: 1 }), 0, "identical rounds tie");
});

test("progressOf defaults missing fields instead of producing NaN", () => {
    assert.deepEqual(progressOf({}), { score: 0, moves: 0, revision: 1 });
});
