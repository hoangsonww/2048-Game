(function exposeGameEngine(root, factory) {
    const engine = factory();
    if (typeof module === "object" && module.exports) module.exports = engine;
    if (root) root.Game2048Engine = engine;
})(typeof globalThis !== "undefined" ? globalThis : this, () => {
    "use strict";

    const SIZE = 4;
    const DIRECTIONS = ["up", "down", "left", "right"];

    function createEmptyBoard() {
        return Array(SIZE * SIZE).fill(0);
    }

    function isTile(value) {
        return Number.isInteger(value) && value >= 0 && (value === 0 || (value & (value - 1)) === 0);
    }

    function isValidBoard(board) {
        return Array.isArray(board) && board.length === SIZE * SIZE && board.every(isTile);
    }

    function assertBoard(board) {
        if (!isValidBoard(board)) throw new TypeError("Board must contain sixteen non-negative power-of-two tiles.");
    }

    function mergeLine(line) {
        if (!Array.isArray(line) || line.length !== SIZE || !line.every(isTile)) {
            throw new TypeError("Line must contain four valid tiles.");
        }
        const compact = line.filter(Boolean);
        const result = [];
        let gained = 0;
        for (let index = 0; index < compact.length; index += 1) {
            if (compact[index] === compact[index + 1]) {
                const merged = compact[index] * 2;
                result.push(merged);
                gained += merged;
                index += 1;
            } else {
                result.push(compact[index]);
            }
        }
        return { line: result.concat(Array(SIZE - result.length).fill(0)), gained };
    }

    function calculateMove(board, direction) {
        assertBoard(board);
        if (!DIRECTIONS.includes(direction)) throw new TypeError(`Unsupported direction: ${direction}`);
        const next = createEmptyBoard();
        let gained = 0;
        for (let outer = 0; outer < SIZE; outer += 1) {
            const original = [];
            for (let inner = 0; inner < SIZE; inner += 1) {
                const row = direction === "left" || direction === "right" ? outer : inner;
                const column = direction === "left" || direction === "right" ? inner : outer;
                original.push(board[row * SIZE + column]);
            }
            const shouldReverse = direction === "right" || direction === "down";
            const input = shouldReverse ? [...original].reverse() : original;
            const merged = mergeLine(input);
            gained += merged.gained;
            const output = shouldReverse ? merged.line.reverse() : merged.line;
            for (let inner = 0; inner < SIZE; inner += 1) {
                const row = direction === "left" || direction === "right" ? outer : inner;
                const column = direction === "left" || direction === "right" ? inner : outer;
                next[row * SIZE + column] = output[inner];
            }
        }
        return { board: next, gained };
    }

    function addRandomTile(board, random = Math.random) {
        assertBoard(board);
        const next = [...board];
        const empty = next.map((value, index) => value === 0 ? index : -1).filter(index => index >= 0);
        if (!empty.length) return next;
        const locationRoll = Math.max(0, Math.min(0.999999999, Number(random())));
        const index = empty[Math.floor(locationRoll * empty.length)];
        next[index] = Number(random()) < 0.9 ? 2 : 4;
        return next;
    }

    function isGameOver(board) {
        assertBoard(board);
        if (board.includes(0)) return false;
        for (let row = 0; row < SIZE; row += 1) {
            for (let column = 0; column < SIZE; column += 1) {
                const value = board[row * SIZE + column];
                if (column < SIZE - 1 && value === board[row * SIZE + column + 1]) return false;
                if (row < SIZE - 1 && value === board[(row + 1) * SIZE + column]) return false;
            }
        }
        return true;
    }

    function availableMoves(board) {
        assertBoard(board);
        return DIRECTIONS.filter(direction => calculateMove(board, direction).board.some((value, index) => value !== board[index]));
    }

    return { SIZE, DIRECTIONS, createEmptyBoard, isValidBoard, mergeLine, calculateMove, addRandomTile, isGameOver, availableMoves };
});
