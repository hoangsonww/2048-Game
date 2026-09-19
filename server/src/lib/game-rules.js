/**
 * The server's copy of the rules that matter for validation.
 *
 * This is deliberately *not* a full engine. The server never plays a move; it
 * only has to answer two questions about data a client sent it: "could this
 * board exist?" and "could this score plausibly belong to that board?". Those
 * are the only two questions, so those are the only two answers implemented.
 *
 * The board predicate is the same one the web engine uses — a tile is zero or
 * a power of two — which is what lets a corrupt cloud save be rejected by the
 * identical rule that rejects a corrupt local save. See ARCHITECTURE.md,
 * "Validation at the boundary".
 */
export const SIZE = 4;
export const CELL_COUNT = SIZE * SIZE;
export const DIRECTIONS = Object.freeze(["up", "down", "left", "right"]);
export const WINNING_TILE = 2048;

/** The highest tile a 4x4 board can physically hold is 2^17 = 131072. */
export const MAX_TILE = 131_072;

export function isTileValue(value) {
    return Number.isInteger(value)
        && value >= 0
        && value <= MAX_TILE
        && (value === 0 || (value & (value - 1)) === 0);
}

export function isValidBoard(board) {
    return Array.isArray(board) && board.length === CELL_COUNT && board.every(isTileValue);
}

/** Accepts either the flat 16-cell form (web) or the nested 4x4 form (natives). */
export function normalizeBoard(board) {
    if (isValidBoard(board)) return [...board];
    if (Array.isArray(board) && board.length === SIZE && board.every(row => Array.isArray(row) && row.length === SIZE)) {
        const flat = board.flat();
        if (isValidBoard(flat)) return flat;
    }
    return null;
}

export function toGrid(board) {
    return Array.from({ length: SIZE }, (_, row) => board.slice(row * SIZE, row * SIZE + SIZE));
}

export function highestTile(board) {
    return board.reduce((highest, value) => (value > highest ? value : highest), 0);
}

export function emptyCellCount(board) {
    return board.reduce((count, value) => count + (value === 0 ? 1 : 0), 0);
}

export function hasWon(board) {
    return highestTile(board) >= WINNING_TILE;
}

export function isGameOver(board) {
    if (board.includes(0)) return false;
    for (let row = 0; row < SIZE; row += 1) {
        for (let column = 0; column < SIZE; column += 1) {
            const value = board[row * SIZE + column];
            if (column + 1 < SIZE && board[row * SIZE + column + 1] === value) return false;
            if (row + 1 < SIZE && board[(row + 1) * SIZE + column] === value) return false;
        }
    }
    return true;
}

/**
 * The theoretical maximum score a board could have reached.
 *
 * Building a tile of value `v` costs `v * (log2(v) - 1)` points, because each
 * merge that produced it also had to produce every tile below it. Summing that
 * over the board gives a ceiling no honest game can exceed. Spawned 4s reduce
 * the real figure, so this is a generous bound used to reject the obviously
 * fabricated rather than to score the game — the client is still authoritative
 * for its own single-player total.
 */
export function maximumPlausibleScore(board) {
    return board.reduce((total, value) => {
        if (value < 4) return total;
        return total + value * (Math.log2(value) - 1);
    }, 0);
}

/**
 * @typedef {object} ScorePlausibility
 * @property {boolean} plausible
 * @property {number} ceiling
 * @property {string} [reason]
 */

/** @returns {ScorePlausibility} */
export function checkScorePlausibility(board, score) {
    const ceiling = maximumPlausibleScore(board);
    if (score < 0) return { plausible: false, ceiling, reason: "A score cannot be negative." };
    if (score > ceiling) {
        return {
            plausible: false,
            ceiling,
            reason: `A board whose highest tile is ${highestTile(board)} cannot have scored more than ${Math.floor(ceiling)}.`
        };
    }
    return { plausible: true, ceiling };
}

/**
 * Board fingerprint used for idempotent score submission and for spotting a
 * client that replays the same finished round to farm the leaderboard.
 */
export function boardSignature(board) {
    return board.map(value => value.toString(36)).join("-");
}

export function summarizeBoard(board) {
    return {
        highestTile: highestTile(board),
        emptyCells: emptyCellCount(board),
        won: hasWon(board),
        gameOver: isGameOver(board)
    };
}

export default {
    SIZE,
    CELL_COUNT,
    DIRECTIONS,
    WINNING_TILE,
    MAX_TILE,
    isTileValue,
    isValidBoard,
    normalizeBoard,
    toGrid,
    highestTile,
    emptyCellCount,
    hasWon,
    isGameOver,
    maximumPlausibleScore,
    checkScorePlausibility,
    boardSignature,
    summarizeBoard
};
