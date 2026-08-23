"use strict";

// Coverage for Web-Version/script.js — the controller that wires the engine to
// the page. The engine suites prove the rules; these prove that a keypress, a
// swipe, a button, or a corrupt saved game each end up doing the right thing.

const test = require("node:test");
const assert = require("node:assert/strict");
const { loadController } = require("./helpers/fake-dom.js");

const STORAGE_KEY = "game2048-state-v2";
const BEST_KEY = "highScore";

const board = values => {
    const next = Array(16).fill(0);
    for (const [index, value] of Object.entries(values)) next[Number(index)] = value;
    return next;
};

const savedGame = (values, extra = {}) => ({
    [STORAGE_KEY]: JSON.stringify({ board: board(values), score: 0, best: 0, won: false, ...extra })
});

// MARK: - Start-up

test("a first visit starts a new game with two tiles", () => {
    const app = loadController();
    const state = app.state();
    assert.equal(state.board.flat().filter(Boolean).length, 2);
    assert.equal(state.score, 0);
    assert.equal(state.mode, "playing");
    assert.match(app.status(), /New game started/);
});

test("the board renders sixteen labelled cells with grid semantics", () => {
    const app = loadController();
    const cells = app.cells();
    assert.equal(cells.length, 16);
    assert.equal(app.grid.children.length, 4, "four rows");
    for (const cell of cells) {
        assert.equal(cell.getAttribute("role"), "gridcell");
        assert.match(cell.getAttribute("aria-label"), /^(Tile \d+|Empty cell)$/);
    }
    assert.equal(app.grid.children[0].getAttribute("role"), "row");
    assert.equal(app.grid.children[0].getAttribute("aria-rowindex"), "1");
});

test("a saved round is restored rather than replaced", () => {
    const app = loadController({
        storage: { [STORAGE_KEY]: JSON.stringify({ board: board({ 0: 8, 5: 16 }), score: 120, best: 300, won: true }) }
    });
    const state = app.state();
    assert.equal(state.board[0][0], 8);
    assert.equal(state.score, 120);
    assert.equal(state.best, 300);
    assert.match(app.status(), /Saved game restored/);
});

test("a corrupt saved game is discarded and the key removed", () => {
    const app = loadController({ storage: { [STORAGE_KEY]: "{not json" } });
    assert.match(app.status(), /New game started/);
    assert.equal(app.state().board.flat().filter(Boolean).length, 2);
});

test("a structurally invalid saved board is ignored", () => {
    const app = loadController({ storage: { [STORAGE_KEY]: JSON.stringify({ board: [1, 2, 3], score: 5 }) } });
    assert.match(app.status(), /New game started/);
    assert.equal(app.state().score, 0);
});

test("a saved score that is negative or not an integer is clamped to zero", () => {
    for (const score of [-10, 1.5, "40", null]) {
        const app = loadController({ storage: savedGame({ 0: 2, 1: 4 }, { score }) });
        assert.equal(app.state().score, 0, `score ${JSON.stringify(score)} must not be trusted`);
    }
});

test("the best score is the larger of the saved round and the standalone record", () => {
    const app = loadController({
        storage: { ...savedGame({ 0: 2, 1: 4 }, { best: 50 }), [BEST_KEY]: "900" }
    });
    assert.equal(app.state().best, 900);
});

test("a restored round that is already lost shows the end-of-round message", () => {
    const locked = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    const app = loadController({
        storage: { [STORAGE_KEY]: JSON.stringify({ board: locked, score: 99, best: 99, won: false }) }
    });
    assert.equal(app.elements.gameMessage.hidden, false);
    assert.equal(app.elements.messageTitle.textContent, "No more moves");
    assert.equal(app.state().mode, "game-over");
});

// MARK: - Moving

test("every arrow key and its WASD twin moves the board", () => {
    for (const [key, direction] of [
        ["ArrowUp", "up"], ["w", "up"], ["W", "up"],
        ["ArrowDown", "down"], ["s", "down"], ["S", "down"],
        ["ArrowLeft", "left"], ["a", "left"], ["A", "left"],
        ["ArrowRight", "right"], ["d", "right"], ["D", "right"]
    ]) {
        const app = loadController({ storage: savedGame({ 4: 2, 5: 2 }) });
        const event = app.key(key);
        assert.equal(event.prevented, 1, `${key} must stop the page scrolling`);
        assert.notEqual(app.status(), "", `${key} should have announced a ${direction} move`);
    }
});

test("an unmapped key is ignored", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    const before = app.state();
    const event = app.key("q");
    assert.equal(event.prevented, 0);
    assert.deepEqual(app.state().board, before.board);
});

test("keys are ignored while the confirmation dialog is open", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    app.elements.newGameDialog.open = true;
    const event = app.key("ArrowLeft");
    assert.equal(event.prevented, 0, "the dialog owns the keyboard while it is up");
});

test("f toggles fullscreen in both directions", () => {
    const app = loadController();
    app.key("f");
    assert.equal(app.fullscreen.requested, 1);

    app.document.fullscreenElement = {};
    app.key("F");
    assert.equal(app.fullscreen.exited, 1);
});

test("a direction button performs the same move as the key", () => {
    const app = loadController({ storage: savedGame({ 12: 2, 13: 2 }) });
    app.directionButtons.find(button => button.dataset.direction === "left").dispatch("click");
    assert.match(app.status(), /Merged for 4 points/);
    assert.equal(app.state().score, 4);
});

test("a merge scores, and a plain slide announces without scoring", () => {
    const merging = loadController({ storage: savedGame({ 0: 4, 1: 4 }) });
    merging.key("ArrowLeft");
    assert.equal(merging.state().score, 8);
    assert.match(merging.status(), /Merged for 8 points/);

    const sliding = loadController({ storage: savedGame({ 3: 2 }) });
    sliding.key("ArrowLeft");
    assert.equal(sliding.state().score, 0);
    assert.match(sliding.status(), /^Moved left\.$/);
});

test("a blocked direction changes nothing and says so", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 4, 2: 8, 3: 16 }) });
    const before = app.state();
    app.key("ArrowLeft");
    assert.equal(app.status(), "No tiles can move left.");
    assert.deepEqual(app.state().board, before.board, "a rejected move must not spawn a tile");
    assert.equal(app.state().canUndo, false);
});

test("the score display is formatted for humans", () => {
    const app = loadController({ storage: savedGame({ 0: 1024, 1: 1024 }) });
    app.key("ArrowLeft");
    assert.equal(app.elements.score.textContent, (2048).toLocaleString());
    assert.equal(app.elements.highScore.textContent, (2048).toLocaleString());
});

// MARK: - Undo

test("undo is disabled until a move is made and consumed after one use", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    assert.equal(app.elements.undoButton.disabled, true);

    app.key("ArrowLeft");
    assert.equal(app.elements.undoButton.disabled, false);
    const afterMove = app.state();

    app.elements.undoButton.dispatch("click");
    assert.equal(app.elements.undoButton.disabled, true);
    assert.equal(app.state().score, 0);
    assert.notDeepEqual(app.state().board, afterMove.board);
    assert.match(app.status(), /Last move undone/);

    app.elements.undoButton.dispatch("click");
    assert.equal(app.state().score, 0, "a second undo is a no-op");
});

test("undo restores the exact board and score from before the move", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2, 8: 4 }) });
    const before = app.state();
    app.key("ArrowLeft");
    app.elements.undoButton.dispatch("click");
    assert.deepEqual(app.state().board, before.board);
    assert.equal(app.state().score, before.score);
});

test("undo is persisted, so a reload does not resurrect the move", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    app.key("ArrowLeft");
    app.elements.undoButton.dispatch("click");
    assert.deepEqual(app.saved().board, app.state().board.flat());
});

// MARK: - New game

test("a new game is immediate when nothing is at stake", () => {
    const app = loadController();
    app.elements.newGameButton.dispatch("click");
    assert.equal(app.elements.newGameDialog.open, false, "no round in progress, so no confirmation");
    assert.match(app.status(), /New game started/);
});

test("a round in progress must be confirmed before it is discarded", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    app.key("ArrowLeft");
    assert.ok(app.state().score > 0);

    app.elements.newGameButton.dispatch("click");
    assert.equal(app.elements.newGameDialog.open, true);
    assert.ok(app.state().score > 0, "the board is untouched until the user confirms");

    app.elements.confirmNewGame.dispatch("click");
    assert.equal(app.state().score, 0);
});

test("a new game keeps the best score and clears undo", () => {
    const app = loadController({ storage: savedGame({ 0: 1024, 1: 1024 }) });
    app.key("ArrowLeft");
    const best = app.state().best;

    app.elements.confirmNewGame.dispatch("click");
    assert.equal(app.state().score, 0);
    assert.equal(app.state().best, best, "the record survives a new round");
    assert.equal(app.state().canUndo, false);
    assert.equal(app.elements.gameMessage.hidden, true);
});

// MARK: - Win and loss

test("reaching 2048 shows a win that can be played through", () => {
    const app = loadController({ storage: savedGame({ 0: 1024, 1: 1024 }) });
    app.key("ArrowLeft");

    assert.equal(app.elements.gameMessage.hidden, false);
    assert.equal(app.elements.messageTitle.textContent, "You made 2048");
    assert.equal(app.elements.messageSecondary.hidden, false, "continuing must be offered");
    assert.equal(app.elements.messagePrimary.textContent, "New game");
    assert.equal(app.elements.messagePrimary.focusCount, 1, "the message takes focus when it appears");
    assert.equal(app.state().mode, "won");

    app.elements.messageSecondary.dispatch("click");
    assert.equal(app.elements.gameMessage.hidden, true);
    assert.match(app.status(), /4096/);
    assert.equal(app.state().mode, "playing");
});

test("the win banner is shown once, not on every later move", () => {
    const app = loadController({ storage: savedGame({ 0: 1024, 1: 1024, 12: 2 }) });
    app.key("ArrowLeft");
    app.elements.messageSecondary.dispatch("click");

    app.key("ArrowDown");
    assert.equal(app.elements.gameMessage.hidden, true, "the goal was already announced");
});

test("a full board with no move left ends the round", () => {
    // One gap, in the only row a left swipe changes. The swipe repacks that row
    // and the spawned tile fills the cell it vacated, leaving a checkerboard
    // with no equal neighbour in any direction.
    const nearlyLocked = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 0, 2, 4];
    const app = loadController({
        storage: { [STORAGE_KEY]: JSON.stringify({ board: nearlyLocked, score: 500, best: 500, won: false }) },
        random: () => 0
    });

    app.key("ArrowLeft");
    assert.equal(app.state().mode, "game-over");
    assert.equal(app.elements.messageTitle.textContent, "No more moves");
    assert.equal(app.elements.messageSecondary.hidden, true, "there is nothing to continue into");
    assert.equal(app.elements.messagePrimary.textContent, "Try again");
    assert.match(app.elements.messageBody.textContent, /Final score/);
});

test("a finished round rejects further moves", () => {
    const locked = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    const app = loadController({
        storage: { [STORAGE_KEY]: JSON.stringify({ board: locked, score: 10, best: 10, won: false }) }
    });
    const before = app.state();
    for (const key of ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"]) app.key(key);
    assert.deepEqual(app.state().board, before.board);
});

// MARK: - Touch

test("a swipe past the threshold moves in the dominant axis", () => {
    for (const [dx, dy, expected] of [[60, 0, "right"], [-60, 0, "left"], [0, 60, "down"], [0, -60, "up"]]) {
        const app = loadController({ storage: savedGame({ 5: 2, 6: 2 }) });
        app.swipe(dx, dy);
        assert.match(app.status(), new RegExp(expected), `(${dx}, ${dy}) should read as ${expected}`);
    }
});

test("a diagonal swipe resolves to its larger component", () => {
    const app = loadController({ storage: savedGame({ 5: 2, 6: 2 }) });
    app.swipe(60, 20);
    assert.match(app.status(), /right/);
});

test("a swipe shorter than the threshold is ignored", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    const before = app.state();
    app.swipe(20, 20);
    assert.deepEqual(app.state().board, before.board);
});

test("a touchend without a touchstart does nothing", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    const before = app.state();
    app.grid.dispatch("touchend", { changedTouches: [{ clientX: 500, clientY: 500 }] });
    assert.deepEqual(app.state().board, before.board);
});

/**
 * The board owns its gesture: a swipe must move tiles, never scroll the page.
 * `touch-action: none` is the primary defence and this handler is the fallback,
 * so it has to be non-passive or `preventDefault` would be ignored.
 */
test("touchmove is non-passive and suppresses scrolling during a board swipe", () => {
    const app = loadController();
    assert.equal(app.grid.isPassive("touchmove"), false, "a passive listener cannot prevent scrolling");

    app.grid.dispatch("touchstart", { changedTouches: [{ clientX: 10, clientY: 10 }] });
    const moved = app.grid.dispatch("touchmove", { cancelable: true, prevented: 0, preventDefault() { this.prevented += 1; } });
    assert.equal(moved.prevented, 1);
});

test("touchmove leaves the page alone when no board swipe is in progress", () => {
    const app = loadController();
    const event = app.grid.dispatch("touchmove", { cancelable: true, prevented: 0, preventDefault() { this.prevented += 1; } });
    assert.equal(event.prevented, 0, "scrolling elsewhere must not be blocked");
});

test("an uncancelable touchmove is left alone", () => {
    const app = loadController();
    app.grid.dispatch("touchstart", { changedTouches: [{ clientX: 10, clientY: 10 }] });
    const event = app.grid.dispatch("touchmove", { cancelable: false, prevented: 0, preventDefault() { this.prevented += 1; } });
    assert.equal(event.prevented, 0);
});

/**
 * A cancelled gesture — a system swipe, an incoming call — has to clear the
 * start point, or the next swipe is measured from a stale origin.
 */
test("a cancelled gesture is forgotten", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    app.grid.dispatch("touchstart", { changedTouches: [{ clientX: 10, clientY: 10 }] });
    app.grid.dispatch("touchcancel", {});

    const before = app.state();
    app.grid.dispatch("touchend", { changedTouches: [{ clientX: 300, clientY: 10 }] });
    assert.deepEqual(app.state().board, before.board, "the stale origin must not produce a move");
});

// MARK: - Rendering and persistence

test("a new or changed tile is flagged for the pop animation, and only then", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    app.key("ArrowLeft");
    assert.ok(app.cells().some(cell => cell.classList.contains("pop")), "the merged tile animates");

    app.redraw();
    assert.ok(app.cells().every(cell => !cell.classList.contains("pop")), "a redraw must not re-animate");
});

test("the grid is built once and then reused", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    const [firstCell] = app.cells();
    app.key("ArrowLeft");
    assert.equal(app.cells().length, 16);
    assert.equal(app.cells()[0], firstCell, "cells are updated in place, not rebuilt");
});

test("every move is written to storage along with the best score", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    app.key("ArrowLeft");

    const saved = app.saved();
    assert.deepEqual(saved.board, app.state().board.flat());
    assert.equal(saved.score, 4);
    assert.equal(saved.best, 4);
    assert.equal(app.localStorage.getItem("highScore"), "4");
});

test("the state dump describes the board it renders", () => {
    const app = loadController({ storage: savedGame({ 0: 2, 1: 2 }) });
    const state = app.state();

    assert.match(state.coordinateSystem, /4x4/);
    assert.equal(state.board.length, 4);
    assert.ok(state.board.every(row => row.length === 4));
    assert.deepEqual(state.board.flat(), app.board());
    assert.ok(Array.isArray(state.availableMoves));
    assert.ok(state.availableMoves.includes("left"));
});
