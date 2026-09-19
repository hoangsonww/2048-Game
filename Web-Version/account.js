// The account, sync, and leaderboard surface for the web app.
//
// This file owns the DOM; `cloud.js` owns the network. Neither owns a game
// rule. The controller in `script.js` exposes exactly one bridge —
// `window.Game2048Game` — and everything here goes through it, which is what
// makes the whole cloud layer removable: delete this file and `cloud.js`,
// drop two script tags, and a complete offline 2048 remains.
//
// Every dependency is injected for the same reason the engine's randomness is:
// so the whole surface, including the failure paths, is reachable from
// `node --test` without a browser.
(function exposeAccountUI(root, factory) {
    "use strict";
    const account = factory();
    if (typeof module === "object" && module.exports) module.exports = account;
    if (root) root.Game2048Account = account;
})(typeof globalThis !== "undefined" ? globalThis : this, () => {
    "use strict";

    const PERIODS = [
        { key: "daily", label: "Today" },
        { key: "weekly", label: "This week" },
        { key: "all", label: "All time" }
    ];

    /** Debounce that survives being called during teardown. */
    function debounce(run, delay, setTimer, clearTimer) {
        let handle = null;
        const debounced = (...args) => {
            if (handle !== null) clearTimer(handle);
            handle = setTimer(() => {
                handle = null;
                run(...args);
            }, delay);
        };
        debounced.cancel = () => {
            if (handle !== null) clearTimer(handle);
            handle = null;
        };
        return debounced;
    }

    function formatNumber(value) {
        return Number(value ?? 0).toLocaleString();
    }

    /**
     * @param {object} options
     * @param {Document} options.document
     * @param {object} options.cloud A client from `cloud.js`.
     * @param {object} options.game The `window.Game2048Game` bridge.
     */
    function createAccountUI({ document, cloud, game, setTimeout: setTimer = setTimeout, clearTimeout: clearTimer = clearTimeout, syncDelay = 2500 }) {
        const byId = id => document.getElementById(id);

        const elements = {
            accountButton: byId("accountButton"),
            accountButtonLabel: byId("accountButtonLabel"),
            leaderboardButton: byId("leaderboardButton"),
            cloudStatus: byId("cloudStatus"),

            banner: byId("cloudBanner"),
            bannerCreate: byId("cloudBannerCreate"),
            bannerSignIn: byId("cloudBannerSignIn"),
            bannerDismiss: byId("cloudBannerDismiss"),

            authDialog: byId("authDialog"),
            authForm: byId("authForm"),
            authTitle: byId("authTitle"),
            authIntro: byId("authIntro"),
            authUsernameField: byId("authUsernameField"),
            authUsername: byId("authUsername"),
            authEmailField: byId("authEmailField"),
            authEmail: byId("authEmail"),
            authIdentifierField: byId("authIdentifierField"),
            authIdentifier: byId("authIdentifier"),
            authPassword: byId("authPassword"),
            authSubmit: byId("authSubmit"),
            authSwitch: byId("authSwitch"),
            authCancel: byId("authCancel"),
            authError: byId("authError"),

            accountDialog: byId("accountDialog"),
            accountName: byId("accountName"),
            accountEmail: byId("accountEmail"),
            accountSummary: byId("accountSummary"),
            accountSync: byId("accountSync"),
            accountSyncNow: byId("accountSyncNow"),
            accountSignOut: byId("accountSignOut"),
            accountClose: byId("accountClose"),

            leaderboardDialog: byId("leaderboardDialog"),
            leaderboardPeriods: byId("leaderboardPeriods"),
            leaderboardList: byId("leaderboardList"),
            leaderboardNote: byId("leaderboardNote"),
            leaderboardClose: byId("leaderboardClose")
        };

        let mode = "register";
        let period = "all";
        let state = cloud.getState();
        let busy = false;

        function setStatus(message) {
            if (elements.cloudStatus) elements.cloudStatus.textContent = message;
        }

        function setError(message) {
            if (!elements.authError) return;
            elements.authError.textContent = message ?? "";
            elements.authError.hidden = !message;
        }

        /* ------------------------------------------------------------ */
        /* Rendering                                                     */
        /* ------------------------------------------------------------ */

        function renderBanner() {
            if (!elements.banner) return;
            // The prompt is an invitation, never a gate. It disappears the
            // moment a player signs in or says no, and the game behind it was
            // always fully playable.
            elements.banner.hidden = state.signedIn || cloud.promptDismissed() || !state.available;
        }

        function renderAccountButton() {
            if (!elements.accountButton) return;
            const label = state.signedIn ? state.user.displayName || state.user.username : "Sign in";
            if (elements.accountButtonLabel) elements.accountButtonLabel.textContent = label;
            elements.accountButton.setAttribute(
                "aria-label",
                state.signedIn ? `Account: ${label}` : "Sign in or create an account"
            );
        }

        function renderStatus() {
            if (!state.available) {
                setStatus("Offline play only — this browser cannot reach the cloud.");
                return;
            }
            if (!state.signedIn) {
                setStatus("Playing on this device. Your round is saved locally.");
                return;
            }

            const resolutionText = {
                uploaded: "Round saved to your account.",
                downloaded: "Restored the round from your account.",
                in_sync: "Everything is in sync.",
                conflicted: "Two devices had different rounds — the further one was kept, and the other is safe in your saves."
            }[state.lastResolution];

            setStatus(state.lastError ? `${state.lastError}` : resolutionText ?? `Signed in as ${state.user.username}.`);
        }

        function renderAccountDialog() {
            if (!state.signedIn || !elements.accountName) return;
            const statistics = state.user.statistics ?? {};
            elements.accountName.textContent = state.user.displayName || state.user.username;
            if (elements.accountEmail) elements.accountEmail.textContent = state.user.email ?? "";
            if (elements.accountSummary) {
                elements.accountSummary.textContent =
                    `Best ${formatNumber(statistics.bestScore)} · ${formatNumber(statistics.gamesPlayed)} rounds · highest tile ${formatNumber(statistics.highestTile)}`;
            }
            if (elements.accountSync) {
                elements.accountSync.textContent = state.lastSync
                    ? `Last synced ${new Date(state.lastSync).toLocaleTimeString()}`
                    : "Not synced yet this session.";
            }
        }

        function render() {
            renderBanner();
            renderAccountButton();
            renderStatus();
            renderAccountDialog();
        }

        /* ------------------------------------------------------------ */
        /* Sync                                                          */
        /* ------------------------------------------------------------ */

        async function syncNow(strategy = "auto") {
            if (!cloud.isSignedIn()) return null;
            try {
                const result = await cloud.sync(game.getSave(), strategy);
                // A downloaded round replaces the local one. An upload does
                // not touch the board — the device that sent it is already
                // showing it.
                if (result.resolution === "downloaded" && result.save) game.applySave(result.save);
                return result;
            } catch (error) {
                setStatus(error.message);
                return null;
            }
        }

        const scheduleSync = debounce(() => { syncNow(); }, syncDelay, setTimer, clearTimer);

        async function submitRound(save) {
            if (!cloud.isSignedIn() || save.score <= 0) return;
            try {
                await cloud.submitScore({
                    board: save.board,
                    score: save.score,
                    moves: save.moves,
                    durationSeconds: save.elapsedSeconds
                });
            } catch (_) {
                // A round that fails to reach the leaderboard is a shame, not
                // an error the player needs to action — the score is already
                // on their screen and in local storage.
            }
        }

        function onGameChange(reason, save) {
            if (!cloud.isSignedIn()) return;
            if (reason === "game-over") {
                submitRound(save);
                syncNow();
                return;
            }
            // `restored` comes from a sync we just performed; re-syncing it
            // would be an immediate second round trip saying the same thing.
            if (reason !== "restored" && reason !== "subscribed") scheduleSync();
        }

        /* ------------------------------------------------------------ */
        /* Dialogs                                                       */
        /* ------------------------------------------------------------ */

        function setMode(next) {
            mode = next;
            const registering = mode === "register";
            if (elements.authTitle) elements.authTitle.textContent = registering ? "Create your account" : "Welcome back";
            if (elements.authIntro) {
                elements.authIntro.textContent = registering
                    ? "Keep your board, best score, and streak on every device you play on."
                    : "Sign in to pick up the round you left on another device.";
            }
            if (elements.authUsernameField) elements.authUsernameField.hidden = !registering;
            if (elements.authEmailField) elements.authEmailField.hidden = !registering;
            if (elements.authIdentifierField) elements.authIdentifierField.hidden = registering;
            if (elements.authSubmit) elements.authSubmit.textContent = registering ? "Create account" : "Sign in";
            if (elements.authSwitch) elements.authSwitch.textContent = registering ? "I already have an account" : "Create an account instead";
            setError(null);
        }

        function openAuth(next) {
            setMode(next);
            if (elements.authDialog) elements.authDialog.showModal();
        }

        function openAccount() {
            renderAccountDialog();
            if (elements.accountDialog) elements.accountDialog.showModal();
        }

        async function submitAuth(event) {
            if (event?.preventDefault) event.preventDefault();
            if (busy) return;

            busy = true;
            setError(null);
            if (elements.authSubmit) elements.authSubmit.disabled = true;

            try {
                if (mode === "register") {
                    await cloud.register({
                        username: elements.authUsername?.value?.trim() ?? "",
                        email: elements.authEmail?.value?.trim() ?? "",
                        password: elements.authPassword?.value ?? ""
                    });
                } else {
                    await cloud.login({
                        identifier: elements.authIdentifier?.value?.trim() ?? "",
                        password: elements.authPassword?.value ?? ""
                    });
                }

                if (elements.authPassword) elements.authPassword.value = "";
                if (elements.authDialog) elements.authDialog.close();
                cloud.dismissPrompt();
                // Signing in is exactly when the two sides are most likely to
                // disagree, so it is the moment that runs a full reconciliation
                // rather than a debounced upload.
                await syncNow();
            } catch (error) {
                setError(error.message);
            } finally {
                busy = false;
                if (elements.authSubmit) elements.authSubmit.disabled = false;
            }
        }

        async function signOut() {
            await cloud.logout();
            if (elements.accountDialog) elements.accountDialog.close();
            setStatus("Signed out. Your round stays on this device.");
        }

        /* ------------------------------------------------------------ */
        /* Leaderboard                                                   */
        /* ------------------------------------------------------------ */

        function renderLeaderboard(page) {
            if (!elements.leaderboardList) return;
            elements.leaderboardList.replaceChildren();

            if (!page || page.entries.length === 0) {
                if (elements.leaderboardNote) {
                    elements.leaderboardNote.textContent = "No rounds in this window yet. Finish a game to be the first.";
                }
                return;
            }

            for (const entry of page.entries) {
                const row = document.createElement("li");
                row.className = entry.isViewer ? "leaderboard-row leaderboard-row--you" : "leaderboard-row";

                const rank = document.createElement("span");
                rank.className = "leaderboard-rank";
                rank.textContent = `#${entry.rank}`;

                const name = document.createElement("span");
                name.className = "leaderboard-name";
                name.textContent = entry.displayName || entry.username;

                const score = document.createElement("strong");
                score.className = "leaderboard-score";
                score.textContent = formatNumber(entry.score);

                const tile = document.createElement("span");
                tile.className = "leaderboard-tile";
                tile.textContent = formatNumber(entry.highestTile);

                row.appendChild(rank);
                row.appendChild(name);
                row.appendChild(tile);
                row.appendChild(score);
                elements.leaderboardList.appendChild(row);
            }

            if (elements.leaderboardNote) {
                elements.leaderboardNote.textContent = `${formatNumber(page.summary.players)} players · top score ${formatNumber(page.summary.topScore)}`;
            }
        }

        function renderPeriodButtons() {
            if (!elements.leaderboardPeriods) return;
            for (const button of elements.leaderboardPeriods.querySelectorAll(".period-button")) {
                const active = button.dataset.period === period;
                button.setAttribute("aria-pressed", String(active));
            }
        }

        async function loadLeaderboard() {
            renderPeriodButtons();
            if (elements.leaderboardNote) elements.leaderboardNote.textContent = "Loading…";
            try {
                renderLeaderboard(await cloud.leaderboard({ period, limit: 20 }));
            } catch (error) {
                renderLeaderboard(null);
                if (elements.leaderboardNote) elements.leaderboardNote.textContent = error.message;
            }
        }

        function openLeaderboard() {
            if (elements.leaderboardDialog) elements.leaderboardDialog.showModal();
            return loadLeaderboard();
        }

        /* ------------------------------------------------------------ */
        /* Wiring                                                        */
        /* ------------------------------------------------------------ */

        const listen = (element, type, handler) => element?.addEventListener(type, handler);

        listen(elements.accountButton, "click", () => (cloud.isSignedIn() ? openAccount() : openAuth("register")));
        listen(elements.leaderboardButton, "click", () => openLeaderboard());
        listen(elements.bannerCreate, "click", () => openAuth("register"));
        listen(elements.bannerSignIn, "click", () => openAuth("login"));
        listen(elements.bannerDismiss, "click", () => {
            cloud.dismissPrompt();
            renderBanner();
        });

        listen(elements.authForm, "submit", submitAuth);
        listen(elements.authSwitch, "click", event => {
            if (event?.preventDefault) event.preventDefault();
            setMode(mode === "register" ? "login" : "register");
        });
        listen(elements.authCancel, "click", () => elements.authDialog?.close());

        listen(elements.accountSyncNow, "click", () => syncNow());
        listen(elements.accountSignOut, "click", () => signOut());
        listen(elements.accountClose, "click", () => elements.accountDialog?.close());

        listen(elements.leaderboardClose, "click", () => elements.leaderboardDialog?.close());
        listen(elements.leaderboardPeriods, "click", event => {
            const next = event?.target?.dataset?.period;
            if (!next || next === period) return;
            period = next;
            return loadLeaderboard();
        });

        const unsubscribeCloud = cloud.subscribe(next => {
            state = next;
            render();
        });
        const unsubscribeGame = game.subscribe(onGameChange);

        return {
            /** Restores a session and reconciles, if there is one to restore. */
            async start() {
                setMode("register");
                render();
                if (!state.available) return;
                if (await cloud.restore()) await syncNow();
            },
            openAuth,
            openAccount,
            openLeaderboard,
            syncNow,
            setPeriod(next) {
                period = next;
                return loadLeaderboard();
            },
            destroy() {
                scheduleSync.cancel();
                unsubscribeCloud();
                unsubscribeGame();
            }
        };
    }

    /**
     * Wires the UI to the real page when the markup and the game are both
     * present. Returning null rather than throwing is deliberate: the cloud
     * layer is optional, and a page that ships without its markup should lose
     * the feature, not the game.
     */
    function autoStart(scope) {
        const view = scope ?? (typeof window === "object" ? window : null);
        if (!view?.document || !view.Game2048Cloud || !view.Game2048Game) return null;
        if (!view.document.getElementById("accountButton")) return null;

        let cloud;
        try {
            cloud = view.Game2048Cloud.createCloudClient({ baseUrl: view.GAME2048_API_BASE_URL });
        } catch (_) {
            // No storage at all — private mode in some engines. The game is
            // unaffected; only the cloud surface is unavailable.
            return null;
        }

        const ui = createAccountUI({ document: view.document, cloud, game: view.Game2048Game });
        ui.start();
        view.Game2048AccountUI = ui;
        return ui;
    }

    if (typeof window === "object" && typeof module !== "object") autoStart(window);

    return { createAccountUI, autoStart, PERIODS };
});
