(() => {
    "use strict";

    const { SIZE, createEmptyBoard, isValidBoard, calculateMove, addRandomTile, isGameOver, availableMoves } = window.Game2048Engine;
    // Two completely separate rounds live on this device: the one played
    // signed out, and the one played signed in. They never touch. A player
    // who signs in does not hand their guest board to an account, and a
    // player who signs out gets the guest board back exactly as they left it,
    // best score included. See ARCHITECTURE.md, "Guest and account profiles".
    const PROFILES = {
        guest: { state: "game2048-state-v2", best: "highScore" },
        account: { state: "game2048-state-account-v1", best: "game2048-best-account-v1" }
    };
    let profile = "guest";
    const stateKey = () => PROFILES[profile].state;
    const bestKey = () => PROFILES[profile].best;
    const gridElement = document.getElementById("gridContainer");
    const scoreElement = document.getElementById("score");
    const bestElement = document.getElementById("highScore");
    const undoButton = document.getElementById("undoButton");
    const newGameButton = document.getElementById("newGameButton");
    const soundButton = document.getElementById("soundButton");
    const newGameDialog = document.getElementById("newGameDialog");
    const confirmNewGame = document.getElementById("confirmNewGame");
    const gameMessage = document.getElementById("gameMessage");
    const messageKicker = document.getElementById("messageKicker");
    const messageTitle = document.getElementById("messageTitle");
    const messageBody = document.getElementById("messageBody");
    const messagePrimary = document.getElementById("messagePrimary");
    const messageSecondary = document.getElementById("messageSecondary");
    const statusLine = document.getElementById("statusLine");

    // Optional: tests and stripped embeds may omit sounds.js.
    const sounds = window.Game2048Sounds?.createGameSounds?.() ?? {
        isEnabled: () => true,
        toggle() { return true; },
        move() {}, merge() {}, undo() {}, newGame() {}, win() {}, gameOver() {}, invalid() {}
    };

    function readBest() {
        return Number.parseInt(localStorage.getItem(bestKey()), 10) || 0;
    }

    let state = {
        board: createEmptyBoard(), score: 0, best: readBest(),
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
            const saved = JSON.parse(localStorage.getItem(stateKey()));
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
            localStorage.removeItem(stateKey());
        }
        return false;
    }

    function saveGame() {
        localStorage.setItem(stateKey(), JSON.stringify({ board: state.board, score: state.score, best: state.best, won: state.won, moves: state.moves }));
        localStorage.setItem(bestKey(), String(state.best));
    }

    /** A fresh board, with no announcement and no observer notification. */
    function resetRound() {
        state.board = addRandomTile(addRandomTile(createEmptyBoard()));
        state.score = 0; state.won = false; state.gameOver = false; state.history = null;
        state.moves = 0; state.startedAt = Date.now();
        hideMessage(); saveGame(); render(true);
    }

    function startNewGame() {
        resetRound();
        sounds.newGame();
        announce("New game started. Two tiles are on the board.");
        notify("new-game");
    }

    function describeRoundComplete() {
        showMessage("Round complete", "No more moves", `Final score: ${state.score.toLocaleString()}. Your best is ${state.best.toLocaleString()}.`, false);
    }

    /**
     * Switches the active round to another profile's storage.
     *
     * The profile being left has already been written to its own keys, so
     * nothing it holds is lost, and nothing it holds travels: `best` is
     * re-read from the profile being entered rather than carried across,
     * which is what keeps a guest best score out of an account's statistics.
     */
    function adoptProfile(next) {
        profile = next;
        state.best = readBest();
        state.history = null;
        state.startedAt = Date.now();
        const restored = loadGame();
        if (restored) {
            hideMessage(); render(false);
            if (state.gameOver) describeRoundComplete();
        } else {
            resetRound();
        }
        announce(profile === "account"
            ? "Signed in. This board belongs to your account."
            : "Signed out. The round you were playing on this device is back.");
        notify("profile");
        return restored;
    }

    function renderSoundButton() {
        if (!soundButton) return;
        const on = sounds.isEnabled();
        soundButton.setAttribute("aria-pressed", String(on));
        soundButton.setAttribute("aria-label", on ? "Mute sound" : "Unmute sound");
        soundButton.title = on ? "Mute sound" : "Unmute sound";
        soundButton.classList.toggle("icon-button--muted", !on);
    }

    function move(direction) {
        if (state.gameOver || !["up", "down", "left", "right"].includes(direction)) return false;
        const result = calculateMove(state.board, direction);
        if (result.board.every((value, index) => value === state.board[index])) {
            sounds.invalid();
            announce(`No tiles can move ${direction}.`); return false;
        }
        state.history = cloneSnapshot(); state.board = result.board; state.score += result.gained;
        state.best = Math.max(state.best, state.score); state.board = addRandomTile(state.board);
        state.moves += 1;
        const reachedGoal = state.board.some(value => value >= 2048);
        state.gameOver = isGameOver(state.board);
        saveGame(); render(true);
        // A board that both hits 2048 and has no moves left is game over — same
        // priority as iOS and Android (keep-playing is meaningless with no moves).
        if (state.gameOver) {
            if (reachedGoal && !state.won) { state.won = true; saveGame(); }
            sounds.gameOver();
            describeRoundComplete();
        } else if (reachedGoal && !state.won) {
            state.won = true; saveGame();
            sounds.win();
            showMessage("Goal reached", "You made 2048", "Keep building, or start with a clean board.", true);
        } else {
            if (result.gained) sounds.merge(result.gained);
            else sounds.move();
            announce(result.gained ? `${direction}. Merged for ${result.gained} points.` : `Moved ${direction}.`);
        }
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
        hideMessage(); saveGame(); render(false); sounds.undo(); announce("Last move undone.");
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
        if (state.gameOver) describeRoundComplete();
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

    function fieldOwnsKeyboard(node) {
        if (!node || typeof node !== "object") return false;
        const tag = node.tagName;
        return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || Boolean(node.isContentEditable);
    }

    function handleKey(event) {
        // Auth (and every other) <dialog> owns the keyboard while open. Without
        // this gate, WASD/arrows still drive the board under the sign-in form —
        // including when focus is on a dialog button rather than an input.
        if (fieldOwnsKeyboard(event.target) || fieldOwnsKeyboard(document.activeElement)) return;
        if (document.querySelector("dialog[open]")) return;
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

    // The Web Audio clock only runs after a user gesture, and a context built
    // before one is stuck at time zero — which is what turned a stream of
    // cues into a single burst. Build it here, inside the first real gesture,
    // so the player's very first move is already audible.
    const unlockSound = () => { sounds.unlock?.(); };
    for (const gesture of ["pointerdown", "keydown", "touchstart"]) {
        document.addEventListener(gesture, unlockSound, { capture: true, once: true, passive: true });
    }

    document.addEventListener("keydown", handleKey);
    document.querySelectorAll("[data-direction]").forEach(button => button.addEventListener("click", () => move(button.dataset.direction)));
    undoButton.addEventListener("click", undo); newGameButton.addEventListener("click", requestNewGame);
    confirmNewGame.addEventListener("click", () => startNewGame()); messagePrimary.addEventListener("click", () => startNewGame());
    messageSecondary.addEventListener("click", () => { hideMessage(); announce("Keep going—your next goal is 4096."); });
    soundButton?.addEventListener("click", () => {
        sounds.toggle();
        renderSoundButton();
        announce(sounds.isEnabled() ? "Sound on." : "Sound muted.");
    });
    renderSoundButton();

    window.render_game_to_text = () => JSON.stringify({
        coordinateSystem: "4x4 grid; origin top-left; rows increase downward, columns increase rightward",
        mode: state.gameOver ? "game-over" : (gameMessage.hidden ? "playing" : "won"),
        board: Array.from({ length: SIZE }, (_, row) => state.board.slice(row * SIZE, row * SIZE + SIZE)),
        score: state.score, best: state.best, canUndo: Boolean(state.history), moves: state.moves,
        profile, availableMoves: availableMoves(state.board)
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

        /** Which storage profile the visible round belongs to. */
        getProfile: () => profile,

        /**
         * Raises the signed-in profile's best score to the account's career
         * best.
         *
         * An account whose saved round is gone still has a history, and
         * showing "Best 0" to a player with nine thousand points behind them
         * is the same class of wrong number as showing a guest's best on a
         * brand-new account — just in the other direction.
         */
        adoptCareerBest(best) {
            if (profile !== "account") return false;
            const value = Number.isInteger(best) && best > 0 ? best : 0;
            if (value <= state.best) return false;
            state.best = value;
            saveGame();
            render(false);
            return true;
        },

        /** Whether the visible round is something a player would mind losing. */
        hasProgress: () => state.score > 0 || state.moves > 0,

        /**
         * Parks the guest round and switches to the signed-in one.
         *
         * The guest round is written to its own keys first and then left
         * alone for the whole session, so signing out restores it exactly.
         * Nothing from it is carried into the account: not the board, not the
         * score, and not the best score.
         */
        beginAccountSession({ fresh = false } = {}) {
            if (profile === "account") return "active";
            saveGame();
            // A brand-new sign-in starts from nothing on purpose. Whatever
            // this browser last cached for *an* account is not necessarily
            // this account's, and syncing it up would upload a stranger's
            // board over the round the player actually has.
            if (fresh) {
                localStorage.removeItem(PROFILES.account.state);
                localStorage.removeItem(PROFILES.account.best);
            }
            return adoptProfile("account") ? "restored" : "fresh";
        },

        /**
         * Discards the signed-in round and restores the guest one.
         *
         * The account's round lives on the server; the copy on this device is
         * a cache, and keeping it would hand the next person to sign in on
         * this browser someone else's board.
         */
        endAccountSession() {
            if (profile !== "account") return false;
            localStorage.removeItem(PROFILES.account.state);
            localStorage.removeItem(PROFILES.account.best);
            adoptProfile("guest");
            return true;
        },

        subscribe(listener) {
            changeListeners.add(listener);
            tell(listener, "subscribed");
            return () => changeListeners.delete(listener);
        }
    };

    if (!loadGame()) startNewGame();
    else {
        render(false); announce("Saved game restored. Continue when ready.");
        if (state.gameOver) describeRoundComplete();
        notify("loaded");
    }
})();
