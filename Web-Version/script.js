(() => {
    "use strict";

    const { SIZE, createEmptyBoard, isValidBoard, calculateMove, addRandomTile, isGameOver, availableMoves } = window.Game2048Engine;
    const STORAGE_KEY = "game2048-state-v2";
    const BEST_KEY = "highScore";
    const gridElement = document.getElementById("gridContainer");
    const scoreElement = document.getElementById("score");
    const bestElement = document.getElementById("highScore");
    const undoButton = document.getElementById("undoButton");
    const newGameButton = document.getElementById("newGameButton");
    const newGameDialog = document.getElementById("newGameDialog");
    const confirmNewGame = document.getElementById("confirmNewGame");
    const gameMessage = document.getElementById("gameMessage");
    const messageKicker = document.getElementById("messageKicker");
    const messageTitle = document.getElementById("messageTitle");
    const messageBody = document.getElementById("messageBody");
    const messagePrimary = document.getElementById("messagePrimary");
    const messageSecondary = document.getElementById("messageSecondary");
    const statusLine = document.getElementById("statusLine");

    let state = {
        board: createEmptyBoard(), score: 0,
        best: Number.parseInt(localStorage.getItem(BEST_KEY), 10) || 0,
        won: false, gameOver: false, history: null, moves: 0, startedAt: Date.now()
    };
    let touchStart = null;
    // Cloud integration subscribes here. The set is empty until something does,
    // and a listener that throws must not take a move down with it — the game
    // is the thing that has to keep working.
    const changeListeners = new Set();

    function cloneSnapshot() {
        return { board: [...state.board], score: state.score, won: state.won };
    }

    function tell(listener, reason) {
        try { listener(reason, cloudSave()); } catch (_) { /* a broken observer is not a broken game */ }
    }

    function notify(reason) {
        for (const listener of changeListeners) tell(listener, reason);
    }

    function nonNegativeInteger(value, fallback) {
        return Number.isInteger(value) && value >= 0 ? value : fallback;
    }

    function loadGame() {
        try {
            const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
            const validBoard = isValidBoard(saved?.board);
            if (validBoard) {
                state.board = saved.board;
                state.score = nonNegativeInteger(saved.score, 0);
                state.best = Math.max(state.best, nonNegativeInteger(saved.best, 0));
                state.won = Boolean(saved.won);
                state.moves = nonNegativeInteger(saved.moves, 0);
                state.gameOver = isGameOver(state.board);
                return true;
            }
        } catch (_) {
            localStorage.removeItem(STORAGE_KEY);
        }
        return false;
    }

    function saveGame() {
        localStorage.setItem(STORAGE_KEY, JSON.stringify({ board: state.board, score: state.score, best: state.best, won: state.won, moves: state.moves }));
        localStorage.setItem(BEST_KEY, String(state.best));
    }

    function startNewGame() {
        state.board = addRandomTile(addRandomTile(createEmptyBoard()));
        state.score = 0; state.won = false; state.gameOver = false; state.history = null;
        state.moves = 0; state.startedAt = Date.now();
        hideMessage(); saveGame(); render(true);
        announce("New game started. Two tiles are on the board.");
        notify("new-game");
    }

    function move(direction) {
        if (state.gameOver || !["up", "down", "left", "right"].includes(direction)) return false;
        const result = calculateMove(state.board, direction);
        if (result.board.every((value, index) => value === state.board[index])) {
            announce(`No tiles can move ${direction}.`); return false;
        }
        state.history = cloneSnapshot(); state.board = result.board; state.score += result.gained;
        state.best = Math.max(state.best, state.score); state.board = addRandomTile(state.board);
        state.moves += 1;
        const reachedGoal = state.board.some(value => value >= 2048);
        state.gameOver = isGameOver(state.board);
        saveGame(); render(true);
        if (reachedGoal && !state.won) {
            state.won = true; saveGame();
            showMessage("Goal reached", "You made 2048", "Keep building, or start with a clean board.", true);
        } else if (state.gameOver) {
            showMessage("Round complete", "No more moves", `Final score: ${state.score.toLocaleString()}. Your best is ${state.best.toLocaleString()}.`, false);
        } else announce(result.gained ? `${direction}. Merged for ${result.gained} points.` : `Moved ${direction}.`);
        notify(state.gameOver ? "game-over" : "move");
        return true;
    }

    function undo() {
        if (!state.history) return;
        state.board = state.history.board; state.score = state.history.score; state.won = state.history.won;
        state.gameOver = false; state.history = null;
        // The move count is not rewound. It measures the round the player
        // actually played, and a metric you can lower by pressing undo is not
        // a measurement.
        hideMessage(); saveGame(); render(false); announce("Last move undone.");
        notify("undo");
    }

    /** The shape the cloud client and the native clients all exchange. */
    function cloudSave() {
        return {
            board: [...state.board], score: state.score, bestScore: state.best,
            won: state.won, gameOver: state.gameOver, moves: state.moves,
            elapsedSeconds: Math.max(0, Math.round((Date.now() - state.startedAt) / 1000)),
            undo: state.history ? { board: [...state.history.board], score: state.history.score, won: state.history.won } : null
        };
    }

    /**
     * Replaces the local round with one that came from another device.
     *
     * Validated with the same predicate that guards a corrupt localStorage
     * entry, because a payload from the network is no more trustworthy than
     * one from disk — and is refused the same way rather than half-applied.
     */
    function applyRemoteSave(save) {
        if (!save || !isValidBoard(save.board)) return false;
        state.board = [...save.board];
        state.score = nonNegativeInteger(save.score, 0);
        state.best = Math.max(state.best, nonNegativeInteger(save.bestScore, 0));
        state.won = Boolean(save.won);
        state.moves = nonNegativeInteger(save.moves, 0);
        state.gameOver = isGameOver(state.board);
        state.history = null;
        state.startedAt = Date.now();
        hideMessage(); saveGame(); render(true);
        if (state.gameOver) showMessage("Round complete", "No more moves", `Final score: ${state.score.toLocaleString()}.`, false);
        announce("Restored the round from your account.");
        notify("restored");
        return true;
    }

    function render(animate) {
        if (gridElement.querySelectorAll(".cell").length !== SIZE * SIZE) {
            gridElement.replaceChildren();
            for (let rowIndex = 0; rowIndex < SIZE; rowIndex += 1) {
                const row = document.createElement("div");
                row.className = "board-row";
                row.setAttribute("role", "row");
                row.setAttribute("aria-rowindex", String(rowIndex + 1));
                for (let columnIndex = 0; columnIndex < SIZE; columnIndex += 1) {
                    const cell = document.createElement("div");
                    cell.className = "cell";
                    cell.setAttribute("role", "gridcell");
                    cell.setAttribute("aria-colindex", String(columnIndex + 1));
                    row.appendChild(cell);
                }
                gridElement.appendChild(row);
            }
        }
        [...gridElement.querySelectorAll(".cell")].forEach((cell, index) => {
            const value = state.board[index];
            const previous = Number(cell.dataset.value || 0);
            cell.textContent = value || ""; cell.dataset.value = String(value);
            cell.setAttribute("aria-label", value ? `Tile ${value}` : "Empty cell");
            cell.classList.toggle("pop", Boolean(animate && value && value !== previous));
        });
        scoreElement.textContent = state.score.toLocaleString();
        bestElement.textContent = state.best.toLocaleString();
        undoButton.disabled = !state.history;
    }

    function showMessage(kicker, title, body, canContinue) {
        messageKicker.textContent = kicker; messageTitle.textContent = title; messageBody.textContent = body;
        messagePrimary.textContent = canContinue ? "New game" : "Try again";
        messageSecondary.hidden = !canContinue; gameMessage.hidden = false; messagePrimary.focus();
    }
    function hideMessage() { gameMessage.hidden = true; }
    function announce(message) { statusLine.textContent = message; }
    function requestNewGame() { if (state.score > 0 && !state.gameOver) newGameDialog.showModal(); else startNewGame(); }

    function handleKey(event) {
        if (newGameDialog.open) return;
        const keyMap = { ArrowUp: "up", w: "up", W: "up", ArrowDown: "down", s: "down", S: "down", ArrowLeft: "left", a: "left", A: "left", ArrowRight: "right", d: "right", D: "right" };
        if (keyMap[event.key]) { event.preventDefault(); move(keyMap[event.key]); }
        else if (event.key === "f" || event.key === "F") {
            if (document.fullscreenElement) document.exitFullscreen(); else document.documentElement.requestFullscreen?.();
        }
    }

    gridElement.addEventListener("touchstart", event => {
        const touch = event.changedTouches[0]; touchStart = { x: touch.clientX, y: touch.clientY };
    }, { passive: true });
    // The board sets touch-action: none, which is the primary defence. This
    // non-passive handler is the fallback for engines that still scroll the
    // page during a board swipe. Scoped to the board so page scrolling is
    // unaffected everywhere else.
    gridElement.addEventListener("touchmove", event => {
        if (touchStart && event.cancelable) event.preventDefault();
    }, { passive: false });
    // A cancelled gesture — a system swipe, an incoming call — must clear the
    // start point, or the board keeps suppressing scrolling until the next
    // touchend and the following swipe is measured from a stale origin.
    gridElement.addEventListener("touchcancel", () => { touchStart = null; }, { passive: true });
    gridElement.addEventListener("touchend", event => {
        if (!touchStart) return;
        const touch = event.changedTouches[0]; const dx = touch.clientX - touchStart.x; const dy = touch.clientY - touchStart.y;
        touchStart = null;
        if (Math.max(Math.abs(dx), Math.abs(dy)) < 28) return;
        move(Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? "right" : "left") : (dy > 0 ? "down" : "up"));
    }, { passive: true });

    document.addEventListener("keydown", handleKey);
    document.querySelectorAll("[data-direction]").forEach(button => button.addEventListener("click", () => move(button.dataset.direction)));
    undoButton.addEventListener("click", undo); newGameButton.addEventListener("click", requestNewGame);
    confirmNewGame.addEventListener("click", startNewGame); messagePrimary.addEventListener("click", startNewGame);
    messageSecondary.addEventListener("click", () => { hideMessage(); announce("Keep going—your next goal is 4096."); });

    window.render_game_to_text = () => JSON.stringify({
        coordinateSystem: "4x4 grid; origin top-left; rows increase downward, columns increase rightward",
        mode: state.gameOver ? "game-over" : (gameMessage.hidden ? "playing" : "won"),
        board: Array.from({ length: SIZE }, (_, row) => state.board.slice(row * SIZE, row * SIZE + SIZE)),
        score: state.score, best: state.best, canUndo: Boolean(state.history), moves: state.moves,
        availableMoves: availableMoves(state.board)
    });
    window.advanceTime = () => render(false);

    // The bridge the optional cloud layer talks to. It is a read/write view of
    // the round and nothing more — no rule, no scoring, and no persistence
    // decision lives on the other side of it, so deleting `account.js` and
    // `cloud.js` leaves a complete game behind.
    window.Game2048Game = {
        getSave: cloudSave,
        applySave: applyRemoteSave,
        newGame: startNewGame,
        subscribe(listener) {
            changeListeners.add(listener);
            tell(listener, "subscribed");
            return () => changeListeners.delete(listener);
        }
    };

    if (!loadGame()) startNewGame();
    else {
        render(false); announce("Saved game restored. Continue when ready.");
        if (state.gameOver) showMessage("Round complete", "No more moves", `Final score: ${state.score.toLocaleString()}.`, false);
        notify("loaded");
    }
})();
