"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
    SIZE, DIRECTIONS, createEmptyBoard, isValidBoard, mergeLine,
    calculateMove, addRandomTile, isGameOver, availableMoves
} = require("../../Web-Version/game-engine.js");

test("engine constants and empty board are stable", () => {
    assert.equal(SIZE, 4);
    assert.deepEqual(DIRECTIONS, ["up", "down", "left", "right"]);
    assert.deepEqual(createEmptyBoard(), Array(16).fill(0));
});

test("board validation accepts only sixteen power-of-two tiles", () => {
    assert.equal(isValidBoard(Array(16).fill(0)), true);
    assert.equal(isValidBoard([2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 0, 0, 0, 0]), true);
    assert.equal(isValidBoard(Array(15).fill(0)), false);
    assert.equal(isValidBoard([...Array(15).fill(0), -2]), false);
    assert.equal(isValidBoard([...Array(15).fill(0), 3]), false);
    assert.equal(isValidBoard("not a board"), false);
});

test("mergeLine compacts, merges once, and reports exact score", () => {
    const cases = [
        { input: [0, 0, 0, 0], line: [0, 0, 0, 0], gained: 0 },
        { input: [0, 2, 0, 4], line: [2, 4, 0, 0], gained: 0 },
        { input: [2, 2, 0, 0], line: [4, 0, 0, 0], gained: 4 },
        { input: [2, 2, 2, 0], line: [4, 2, 0, 0], gained: 4 },
        { input: [2, 2, 2, 2], line: [4, 4, 0, 0], gained: 8 },
        { input: [2, 2, 4, 4], line: [4, 8, 0, 0], gained: 12 },
        { input: [4, 4, 8, 0], line: [8, 8, 0, 0], gained: 8 },
        { input: [4, 8, 8, 4], line: [4, 16, 4, 0], gained: 16 }
    ];
    for (const scenario of cases) assert.deepEqual(mergeLine(scenario.input), { line: scenario.line, gained: scenario.gained });
    assert.throws(() => mergeLine([2, 2]), TypeError);
    assert.throws(() => mergeLine([2, 2, 3, 0]), TypeError);
});

test("calculateMove handles all four directions without mutating input", () => {
    const board = [
        2, 0, 2, 2,
        4, 4, 0, 0,
        2, 0, 2, 0,
        0, 0, 0, 0
    ];
    const copy = [...board];
    assert.deepEqual(calculateMove(board, "left"), {
        board: [4, 2, 0, 0, 8, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0], gained: 16
    });
    assert.deepEqual(calculateMove(board, "right"), {
        board: [0, 0, 2, 4, 0, 0, 0, 8, 0, 0, 0, 4, 0, 0, 0, 0], gained: 16
    });
    assert.deepEqual(calculateMove(board, "up").board, [2, 4, 4, 2, 4, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0]);
    assert.deepEqual(calculateMove(board, "down").board, [0, 0, 0, 0, 2, 0, 0, 0, 4, 0, 0, 0, 2, 4, 4, 2]);
    assert.deepEqual(board, copy);
    assert.throws(() => calculateMove(board, "diagonal"), TypeError);
    assert.throws(() => calculateMove([2], "left"), TypeError);
});

test("random tile placement is deterministic at both probability boundaries", () => {
    const empty = createEmptyBoard();
    const first = addRandomTile(empty, sequence([0, 0.899999]));
    const last = addRandomTile(empty, sequence([0.999999, 0.9]));
    assert.equal(first[0], 2);
    assert.equal(last[15], 4);
    assert.deepEqual(empty, createEmptyBoard(), "input remains immutable");

    const full = Array.from({ length: 16 }, (_, index) => 2 ** ((index % 4) + 1));
    assert.deepEqual(addRandomTile(full, () => { throw new Error("random should not be called"); }), full);
    assert.notEqual(addRandomTile(full), full, "full boards are copied instead of aliased");
});

test("game-over detection distinguishes empty cells and horizontal or vertical merges", () => {
    const locked = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    assert.equal(isGameOver(locked), true);
    assert.equal(isGameOver([...locked.slice(0, 15), 0]), false);
    assert.equal(isGameOver([2, 2, ...locked.slice(2)]), false);
    const verticalMerge = [...locked];
    verticalMerge[4] = verticalMerge[0];
    assert.equal(isGameOver(verticalMerge), false);
    assert.throws(() => isGameOver(Array(16).fill(3)), TypeError);
});

test("availableMoves reports only directions that change the board", () => {
    const locked = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    assert.deepEqual(availableMoves(locked), []);
    assert.deepEqual(availableMoves([2, 4, 0, 0, ...Array(12).fill(0)]), ["down", "right"]);
    assert.deepEqual(availableMoves([2, 2, ...locked.slice(2)]), ["up", "down", "left", "right"]);
});

function sequence(values) {
    let index = 0;
    return () => values[index++];
}
