"use strict";

// Edge-case coverage for the rules engine. The main suite proves the happy
// paths; these pin the boundaries where a subtle change would still pass every
// ordinary test but break real games.

const test = require("node:test");
const assert = require("node:assert/strict");
const {
    SIZE, DIRECTIONS, createEmptyBoard, isValidBoard, mergeLine,
    calculateMove, addRandomTile, isGameOver, availableMoves
} = require("../../Web-Version/game-engine.js");

const board = values => {
    const next = createEmptyBoard();
    for (const [index, value] of Object.entries(values)) next[Number(index)] = value;
    return next;
};

test("mergeLine never merges a tile that was just created", () => {
    // [2,2,4] must become [4,4] and not [8]: the merged 4 is not eligible again
    // in the same move. This is the single most commonly broken 2048 rule.
    assert.deepEqual(mergeLine([2, 2, 4, 0]), { line: [4, 4, 0, 0], gained: 4 });
    assert.deepEqual(mergeLine([4, 2, 2, 0]), { line: [4, 4, 0, 0], gained: 4 });
    assert.deepEqual(mergeLine([2, 2, 2, 2]), { line: [4, 4, 0, 0], gained: 8 });
    assert.deepEqual(mergeLine([4, 4, 4, 4]), { line: [8, 8, 0, 0], gained: 16 });
});

test("mergeLine compacts gaps without inventing merges", () => {
    assert.deepEqual(mergeLine([0, 2, 0, 4]), { line: [2, 4, 0, 0], gained: 0 });
    assert.deepEqual(mergeLine([0, 0, 0, 2]), { line: [2, 0, 0, 0], gained: 0 });
    assert.deepEqual(mergeLine([0, 0, 0, 0]), { line: [0, 0, 0, 0], gained: 0 });
});

test("mergeLine scores only the newly created tile values", () => {
    assert.equal(mergeLine([8, 8, 0, 0]).gained, 16);
    assert.equal(mergeLine([2, 4, 8, 16]).gained, 0);
    // Two separate merges in one line sum their results.
    assert.equal(mergeLine([2, 2, 8, 8]).gained, 20);
});

test("calculateMove leaves the input board untouched", () => {
    const original = board({ 0: 2, 1: 2 });
    const snapshot = [...original];
    calculateMove(original, "left");
    assert.deepEqual(original, snapshot, "the engine must be free of side effects");
});

test("every direction is a no-op on an empty board", () => {
    const empty = createEmptyBoard();
    for (const direction of DIRECTIONS) {
        const result = calculateMove(empty, direction);
        assert.deepEqual(result.board, empty);
        assert.equal(result.gained, 0);
    }
});

test("a single tile slides to the far edge in each direction", () => {
    const centre = board({ 5: 2 }); // row 1, column 1
    assert.equal(calculateMove(centre, "up").board[1], 2);
    assert.equal(calculateMove(centre, "down").board[13], 2);
    assert.equal(calculateMove(centre, "left").board[4], 2);
    assert.equal(calculateMove(centre, "right").board[7], 2);
});

test("right and down merge from the far edge inward", () => {
    // [2,2,2,0] moving right is [0,0,2,4]: the pair nearest the destination
    // merges first, which is the opposite of the left-moving order.
    const row = board({ 0: 2, 1: 2, 2: 2 });
    assert.deepEqual(calculateMove(row, "right").board.slice(0, 4), [0, 0, 2, 4]);
    assert.deepEqual(calculateMove(row, "left").board.slice(0, 4), [4, 2, 0, 0]);

    const column = board({ 0: 2, 4: 2, 8: 2 });
    const down = calculateMove(column, "down").board;
    assert.deepEqual([down[0], down[4], down[8], down[12]], [0, 0, 2, 4]);
});

test("addRandomTile is deterministic for a supplied generator", () => {
    const empty = createEmptyBoard();
    // First roll picks the slot, second decides the value.
    const alwaysFirstAndTwo = () => 0;
    assert.equal(addRandomTile(empty, alwaysFirstAndTwo)[0], 2);

    let call = 0;
    const lastSlotAndFour = () => (call++ === 0 ? 0.999999999 : 0.95);
    const placed = addRandomTile(empty, lastSlotAndFour);
    assert.equal(placed[15], 4);
});

test("addRandomTile respects the ninety/ten split at its boundary", () => {
    const empty = createEmptyBoard();
    let call = 0;
    const justUnder = () => (call++ === 0 ? 0 : 0.8999);
    assert.equal(addRandomTile(empty, justUnder)[0], 2);

    call = 0;
    const exactlyAt = () => (call++ === 0 ? 0 : 0.9);
    assert.equal(addRandomTile(empty, exactlyAt)[0], 4, "0.9 is not less than 0.9, so it is a four");
});

test("addRandomTile leaves a full board untouched", () => {
    const full = Array.from({ length: 16 }, (_, index) => 2 ** ((index % 11) + 1));
    assert.deepEqual(addRandomTile(full, () => 0), full);
});

test("addRandomTile only ever fills an empty cell", () => {
    const nearlyFull = Array(16).fill(2);
    nearlyFull[7] = 0;
    const filled = addRandomTile(nearlyFull, () => 0.5);
    assert.ok(filled[7] === 2 || filled[7] === 4);
    assert.equal(filled.filter(value => value === 0).length, 0);
});

test("isGameOver needs a full board with no orthogonal pair", () => {
    assert.equal(isGameOver(createEmptyBoard()), false, "an empty cell always allows a move");

    const locked = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    assert.equal(isGameOver(locked), true);

    // A full board with one horizontal pair is still playable.
    const horizontal = [...locked];
    horizontal[1] = 2;
    assert.equal(isGameOver(horizontal), false);

    // And one vertical pair likewise.
    const vertical = [...locked];
    vertical[4] = 2;
    assert.equal(isGameOver(vertical), false);
});

test("availableMoves lists exactly the directions that change the board", () => {
    assert.deepEqual(availableMoves(createEmptyBoard()), []);

    const locked = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    assert.deepEqual(availableMoves(locked), []);

    // A tile already flush left can still move right.
    const leftEdge = board({ 0: 2 });
    const moves = availableMoves(leftEdge);
    assert.ok(moves.includes("right"));
    assert.ok(moves.includes("down"));
    assert.ok(!moves.includes("left"), "it is already as far left as it goes");
    assert.ok(!moves.includes("up"));
});

test("availableMoves agrees with isGameOver on a locked board", () => {
    const locked = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    assert.equal(availableMoves(locked).length === 0, isGameOver(locked));
});

test("the engine rejects structurally invalid boards", () => {
    const invalid = [
        Array(15).fill(0),
        Array(17).fill(0),
        [...Array(15).fill(0), 3],
        [...Array(15).fill(0), -2],
        [...Array(15).fill(0), 1.5],
        [...Array(15).fill(0), "2"]
    ];
    for (const candidate of invalid) {
        assert.equal(isValidBoard(candidate), false, `${JSON.stringify(candidate).slice(0, 40)} must be rejected`);
        assert.throws(() => calculateMove(candidate, "left"));
        assert.throws(() => isGameOver(candidate));
        assert.throws(() => availableMoves(candidate));
    }
});

test("a winning tile is reachable and does not end the game", () => {
    const nearWin = board({ 0: 1024, 1: 1024 });
    const result = calculateMove(nearWin, "left");
    assert.equal(result.board[0], 2048);
    assert.equal(result.gained, 2048);
    assert.equal(isGameOver(result.board), false, "reaching 2048 leaves the board playable");
});
