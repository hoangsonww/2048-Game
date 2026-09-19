import assert from "node:assert/strict";
import test from "node:test";
import {
    boardSignature,
    checkScorePlausibility,
    emptyCellCount,
    hasWon,
    highestTile,
    isGameOver,
    isTileValue,
    isValidBoard,
    maximumPlausibleScore,
    normalizeBoard,
    summarizeBoard,
    toGrid
} from "../../src/lib/game-rules.js";

const EMPTY = new Array(16).fill(0);

test("a tile is zero or a power of two", () => {
    for (const value of [0, 2, 4, 8, 1024, 131_072]) assert.equal(isTileValue(value), true, `${value} should be valid`);
    for (const value of [3, -2, 1.5, "4", null, 262_144]) assert.equal(isTileValue(value), false, `${value} should be rejected`);
});

test("a tile of 1 is rejected even though it is a power of two", () => {
    // 2^0 passes the bitwise test but cannot appear on a 2048 board.
    assert.equal(isTileValue(1), true, "the bitwise predicate accepts 1");
    // The board predicate is the same one the web engine uses, and it accepts
    // 1 too. This test records that deliberately: the clients never produce a
    // 1, and tightening the rule here would diverge from the engine the three
    // clients share.
    assert.equal(isValidBoard([1, ...EMPTY.slice(1)]), true);
});

test("a board is exactly 16 valid cells", () => {
    assert.equal(isValidBoard(EMPTY), true);
    assert.equal(isValidBoard(EMPTY.slice(1)), false, "15 cells is not a board");
    assert.equal(isValidBoard([...EMPTY, 0]), false, "17 cells is not a board");
    assert.equal(isValidBoard(null), false);
    assert.equal(isValidBoard([...EMPTY.slice(1), 3]), false, "a non-power-of-two cell invalidates the board");
});

test("normalizeBoard accepts both the flat and the nested form", () => {
    const flat = [2, 4, 8, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    const nested = [[2, 4, 8, 16], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]];

    assert.deepEqual(normalizeBoard(flat), flat);
    assert.deepEqual(normalizeBoard(nested), flat, "the natives send rows; the server stores flat");
    assert.equal(normalizeBoard([[2, 4], [8, 16]]), null, "a 2x2 grid is not a board");
    assert.equal(normalizeBoard("nope"), null);
});

test("normalizeBoard copies rather than aliasing its input", () => {
    const input = [...EMPTY];
    const output = normalizeBoard(input);
    output[0] = 2048;
    assert.equal(input[0], 0, "the caller's array must not be mutated");
});

test("toGrid splits row-major", () => {
    const board = Array.from({ length: 16 }, (_, index) => (index === 5 ? 2 : 0));
    assert.deepEqual(toGrid(board)[1], [0, 2, 0, 0], "index 5 is row 1, column 1");
});

test("board summaries", () => {
    const board = [2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4, 2, 8, 2, 4];
    assert.equal(highestTile(board), 2048);
    assert.equal(emptyCellCount(board), 0);
    assert.equal(hasWon(board), true);
    assert.equal(highestTile(EMPTY), 0);
    assert.equal(emptyCellCount(EMPTY), 16);
});

test("game over requires a full board and no orthogonal pair", () => {
    const checkerboard = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    assert.equal(isGameOver(checkerboard), true, "a locked checkerboard is game over");

    const withHorizontalPair = [...checkerboard];
    withHorizontalPair[1] = 2;
    assert.equal(isGameOver(withHorizontalPair), false, "a full board with a mergeable pair is still playable");

    const withVerticalPair = [...checkerboard];
    withVerticalPair[4] = 2;
    assert.equal(isGameOver(withVerticalPair), false, "a vertical pair also keeps the round alive");

    const withSpace = [...checkerboard];
    withSpace[15] = 0;
    assert.equal(isGameOver(withSpace), false, "an empty cell is never game over");
});

test("the score ceiling is the cost of building every tile on the board", () => {
    // A 16 costs 16 * (log2(16) - 1) = 48: the merges that made it, and the
    // merges that made those.
    assert.equal(maximumPlausibleScore([16, ...EMPTY.slice(1)]), 48);
    assert.equal(maximumPlausibleScore([2, ...EMPTY.slice(1)]), 0, "a spawned 2 was never merged, so it scored nothing");
    assert.equal(maximumPlausibleScore([4, ...EMPTY.slice(1)]), 4);
    assert.equal(maximumPlausibleScore(EMPTY), 0);
});

test("an impossible score is rejected and a plausible one is not", () => {
    const modest = [2, 4, 8, 16, ...EMPTY.slice(4)];
    assert.equal(checkScorePlausibility(modest, 60).plausible, true);

    const fabricated = checkScorePlausibility(modest, 500_000);
    assert.equal(fabricated.plausible, false);
    assert.match(fabricated.reason, /cannot have scored more than/);

    assert.equal(checkScorePlausibility(modest, -1).plausible, false, "a negative score is never plausible");
});

test("a real endgame board comfortably clears its own score", () => {
    // 512 + 256 + 128 + 64 + 32 + 16 + 8 + 4 sums to a ceiling above 7000, so a
    // genuine 5,600-point round is accepted. This is the case that a naive
    // ceiling gets wrong and flags a real player as a cheat.
    const board = [512, 256, 128, 64, 32, 16, 8, 4, 2, 0, 0, 0, 0, 0, 0, 0];
    assert.equal(checkScorePlausibility(board, 5600).plausible, true);
});

test("the signature distinguishes boards and is stable for one board", () => {
    const board = [2, 4, 8, 16, ...EMPTY.slice(4)];
    const other = [4, 2, 8, 16, ...EMPTY.slice(4)];
    assert.equal(boardSignature(board), boardSignature([...board]));
    assert.notEqual(boardSignature(board), boardSignature(other), "transposed tiles are a different round");
});

test("summarizeBoard reports all four properties at once", () => {
    assert.deepEqual(summarizeBoard([2048, ...EMPTY.slice(1)]), {
        highestTile: 2048,
        emptyCells: 15,
        won: true,
        gameOver: false
    });
});
