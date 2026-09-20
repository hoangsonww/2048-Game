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
    /** How long the guest invite toast stays visible after load. */
    const GUEST_TOAST_MS = 5500;

    function createAccountUI({
        document,
        cloud,
        game,
        setTimeout: setTimer = setTimeout,
        clearTimeout: clearTimer = clearTimeout,
        syncDelay = 800,
        toastDuration = GUEST_TOAST_MS
    }) {
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
            authConfirmField: byId("authConfirmField"),
            authConfirm: byId("authConfirm"),
            authSubmit: byId("authSubmit"),
            authSwitch: byId("authSwitch"),
            authForgot: byId("authForgot"),
            authCancel: byId("authCancel"),
            authDismiss: byId("authDismiss"),
            authError: byId("authError"),

            resetDialog: byId("resetDialog"),
            resetForm: byId("resetForm"),
            resetUsername: byId("resetUsername"),
            resetEmail: byId("resetEmail"),
            resetPassword: byId("resetPassword"),
            resetConfirm: byId("resetConfirm"),
            resetSubmit: byId("resetSubmit"),
            resetCancel: byId("resetCancel"),
            resetDismiss: byId("resetDismiss"),
            resetError: byId("resetError"),

            profileSwitchDialog: byId("profileSwitchDialog"),
            profileSwitchTitle: byId("profileSwitchTitle"),
            profileSwitchBody: byId("profileSwitchBody"),
            profileSwitchConfirm: byId("profileSwitchConfirm"),
            profileSwitchCancel: byId("profileSwitchCancel"),

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
        /** Nested in-flight cloud work: "auth" | "sync" | "leaderboard" | "signout". */
        const busyStack = [];
        /** Session-only: auto-hide does not permanently dismiss the invite. */
        let toastElapsed = false;
        let toastTimer = null;
        /**
         * One reconciliation at a time.
         *
         * Tracked separately from the busy stack because a stored session is
         * already "busy" while it restores, and reading the stack here made a
         * launch-time reconcile decline to run at all — the exact request a
         * returning player most needs.
         */
        let reconciling = false;

        function currentBusy() {
            return busyStack[busyStack.length - 1] ?? null;
        }

        function busyCopy(kind) {
            if (kind === "auth") return mode === "register" ? "Creating account…" : "Signing in…";
            if (kind === "reset") return "Resetting…";
            if (kind === "sync") return "Syncing…";
            if (kind === "leaderboard") return "Loading…";
            return "Signing out…";
        }

        function applyBusy() {
            const kind = currentBusy();
            const authenticating = kind === "auth";
            const syncing = kind === "sync";
            const loadingBoard = kind === "leaderboard";
            const signingOut = kind === "signout";

            if (elements.authDialog) elements.authDialog.setAttribute("aria-busy", authenticating ? "true" : "false");
            if (elements.authForm) elements.authForm.setAttribute("aria-busy", authenticating ? "true" : "false");
            if (elements.authSubmit) {
                elements.authSubmit.disabled = authenticating;
                elements.authSubmit.classList.toggle("is-busy", authenticating);
                elements.authSubmit.textContent = authenticating
                    ? busyCopy("auth")
                    : (mode === "register" ? "Create account" : "Sign in");
            }
            if (elements.authSwitch) elements.authSwitch.disabled = authenticating;
            if (elements.authForgot) elements.authForgot.disabled = authenticating;
            for (const field of [elements.authUsername, elements.authEmail, elements.authIdentifier, elements.authPassword, elements.authConfirm]) {
                if (field) field.disabled = authenticating;
            }

            const resetting = kind === "reset";
            if (elements.resetDialog) elements.resetDialog.setAttribute("aria-busy", resetting ? "true" : "false");
            if (elements.resetSubmit) {
                elements.resetSubmit.disabled = resetting;
                elements.resetSubmit.classList.toggle("is-busy", resetting);
                elements.resetSubmit.textContent = resetting ? "Resetting…" : "Reset password";
            }
            for (const field of [elements.resetUsername, elements.resetEmail, elements.resetPassword, elements.resetConfirm]) {
                if (field) field.disabled = resetting;
            }

            if (elements.accountDialog) elements.accountDialog.setAttribute("aria-busy", (syncing || signingOut) ? "true" : "false");
            if (elements.accountSyncNow) {
                elements.accountSyncNow.disabled = syncing;
                elements.accountSyncNow.classList.toggle("is-busy", syncing);
                elements.accountSyncNow.textContent = syncing ? "Syncing…" : "Sync now";
            }
            if (elements.accountSignOut) {
                elements.accountSignOut.disabled = signingOut;
                elements.accountSignOut.classList.toggle("is-busy", signingOut);
                elements.accountSignOut.textContent = signingOut ? "Signing out…" : "Sign out";
            }

            if (elements.leaderboardDialog) {
                elements.leaderboardDialog.setAttribute("aria-busy", loadingBoard ? "true" : "false");
            }
            if (elements.leaderboardNote) elements.leaderboardNote.classList.toggle("is-busy", loadingBoard);
            if (elements.leaderboardPeriods) {
                for (const button of elements.leaderboardPeriods.querySelectorAll(".period-button")) {
                    button.disabled = loadingBoard;
                }
            }

            if (elements.cloudStatus) {
                elements.cloudStatus.setAttribute("aria-busy", kind && kind !== "leaderboard" ? "true" : "false");
                elements.cloudStatus.classList.toggle("is-busy", Boolean(kind && kind !== "leaderboard"));
            }
            // Busy copy is painted over the real message, never recorded as
            // it: when the work finishes, whatever the work had to say comes
            // back. Without that, an inner step's error was erased by the
            // outer step's spinner text and the player saw "Creating
            // account…" sitting on a screen where nothing was happening.
            paintStatus(kind && kind !== "leaderboard" ? busyCopy(kind) : restingStatus);
        }

        function beginBusy(kind) {
            busyStack.push(kind);
            applyBusy();
        }

        function endBusy() {
            busyStack.pop();
            applyBusy();
        }

        /** The message the surface returns to once nothing is in flight. */
        let restingStatus = "";

        function paintStatus(message) {
            if (elements.cloudStatus) elements.cloudStatus.textContent = message;
        }

        function setStatus(message) {
            restingStatus = message;
            paintStatus(message);
        }

        function setError(message) {
            if (!elements.authError) return;
            elements.authError.textContent = message ?? "";
            elements.authError.hidden = !message;
        }

        function setResetError(message) {
            if (!elements.resetError) return;
            elements.resetError.textContent = message ?? "";
            elements.resetError.hidden = !message;
        }

        /* ------------------------------------------------------------ */
        /* Password fields                                               */
        /* ------------------------------------------------------------ */

        /**
         * Every password-reveal control on the page.
         *
         * A password a player cannot read is a password they mistype, and
         * retyping it into a confirmation field they also cannot read does
         * not help. Each field gets its own toggle, so revealing one does not
         * expose the rest of the form to whoever is standing behind them.
         */
        const revealButtons = [...(document.querySelectorAll?.("[data-reveal]") ?? [])];

        function setRevealed(button, revealed) {
            const field = byId(button?.getAttribute?.("data-reveal") ?? "");
            if (!field) return false;
            field.type = revealed ? "text" : "password";
            button.setAttribute("aria-pressed", String(revealed));
            const noun = button.getAttribute("data-reveal-label") ?? "password";
            const label = `${revealed ? "Hide" : "Show"} ${noun}`;
            button.setAttribute("aria-label", label);
            button.title = label;
            return revealed;
        }

        function toggleReveal(button) {
            const field = byId(button?.getAttribute?.("data-reveal") ?? "");
            return setRevealed(button, field?.type === "password");
        }

        /** Hides every password again when a form closes. */
        function concealPasswords(...fields) {
            for (const field of fields) {
                if (field) field.type = "password";
            }
            for (const button of revealButtons) setRevealed(button, false);
        }

        function clearToastTimer() {
            if (toastTimer !== null) {
                clearTimer(toastTimer);
                toastTimer = null;
            }
        }

        function scheduleToastHide() {
            clearToastTimer();
            if (toastDuration <= 0) return;
            toastTimer = setTimer(() => {
                toastTimer = null;
                toastElapsed = true;
                renderBanner();
            }, toastDuration);
        }

        /* ------------------------------------------------------------ */
        /* Rendering                                                     */
        /* ------------------------------------------------------------ */

        function renderBanner() {
            if (!elements.banner) return;
            // Floating toast on load — never a gate, never layout in the board
            // column. Auto-hides after a few seconds; explicit dismiss persists.
            const eligible = !state.signedIn && !cloud.promptDismissed() && state.available;
            elements.banner.hidden = !eligible || toastElapsed;
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
            if (currentBusy() && currentBusy() !== "leaderboard") {
                // Painted, not recorded: the message underneath is what the
                // surface returns to when the work finishes.
                paintStatus(busyCopy(currentBusy()));
                return;
            }
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
            // Career totals come from the account and from nowhere else. A
            // guest round played on this device before signing in is not part
            // of this account's history, and folding its best score or its
            // highest tile in here is what produced the nonsense of "best
            // 4,312 · 0 rounds" on an account that had never played.
            const statistics = state.user.statistics ?? {};
            const bestScore = statistics.bestScore ?? 0;
            const highestTile = statistics.highestTile ?? 0;
            elements.accountName.textContent = state.user.displayName || state.user.username;
            if (elements.accountEmail) elements.accountEmail.textContent = state.user.email ?? "";
            if (elements.accountSummary) {
                elements.accountSummary.textContent =
                    `Best ${formatNumber(bestScore)} · ${formatNumber(statistics.gamesPlayed)} rounds · highest tile ${formatNumber(highestTile)}`;
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

        function shouldApplyRemote(result) {
            if (!result?.save) return false;
            if (result.resolution === "downloaded") return true;
            // Auto-resolution parks the loser; the winning remote board must
            // still land on this device or Sync now looks broken.
            return result.resolution === "conflicted" && result.winner === "remote";
        }

        async function syncNow(strategy = "auto") {
            if (!cloud.isSignedIn()) return null;
            if (reconciling) return null;
            reconciling = true;
            scheduleSync.cancel();
            beginBusy("sync");
            try {
                const local = game.getSave();
                const result = await cloud.sync(local, strategy);
                if (shouldApplyRemote(result)) game.applySave(result.save);
                // Refresh career totals when the client exposes it; otherwise
                // absorbLocalStats inside cloud.sync already lifted best score.
                if (typeof cloud.refreshUser === "function") {
                    try {
                        await cloud.refreshUser();
                    } catch (_) {
                        /* offline after a successful sync is fine */
                    }
                }
                renderAccountDialog();
                return result;
            } catch (error) {
                setStatus(error.message);
                return null;
            } finally {
                reconciling = false;
                endBusy();
            }
        }

        /** Explicit Sync now: push this device's board. */
        function syncNowPreferred() {
            return syncNow("prefer-local");
        }

        /**
         * Loads the account's round after a sign-in, uploading nothing.
         *
         * The `null` local save is the point. A guest round belongs to the
         * device, not to the account that just signed in on it, so there is
         * nothing here for the server to merge, conflict with, or adopt — it
         * either hands back the round this account already had, or it has
         * none and the fresh board `beginAccountSession` created stands.
         */
        async function adoptAccountRound() {
            if (reconciling) return null;
            reconciling = true;
            scheduleSync.cancel();
            beginBusy("sync");
            try {
                const result = await cloud.sync(null, "auto");
                if (result?.save) game.applySave(result.save);
                if (typeof cloud.refreshUser === "function") {
                    try {
                        await cloud.refreshUser();
                    } catch (_) {
                        /* offline right after signing in is not an auth failure */
                    }
                }
                game.adoptCareerBest?.(cloud.getState().user?.statistics?.bestScore ?? 0);
                renderAccountDialog();
                return result;
            } catch (error) {
                setStatus(error.message);
                return null;
            } finally {
                reconciling = false;
                endBusy();
            }
        }

        const scheduleSync = debounce(() => { syncNow("auto"); }, syncDelay, setTimer, clearTimer);

        async function submitRound(save) {
            if (!cloud.isSignedIn() || save.score <= 0) return;
            try {
                await cloud.submitScore({
                    board: save.board,
                    score: save.score,
                    moves: save.moves,
                    durationSeconds: save.elapsedSeconds
                });
                renderAccountDialog();
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
                syncNow("auto");
                return;
            }
            // `restored` comes from a sync we just performed and `profile`
            // from a session change that syncs explicitly straight after;
            // re-syncing either would be a round trip saying the same thing.
            if (reason !== "restored" && reason !== "subscribed" && reason !== "profile") scheduleSync();
        }

        function flushSyncOnHide() {
            if (!cloud.isSignedIn()) return;
            if (typeof document !== "undefined" && document.visibilityState && document.visibilityState !== "hidden") {
                return;
            }
            scheduleSync.cancel();
            syncNow("auto");
        }

        /* ------------------------------------------------------------ */
        /* Dialogs                                                       */
        /* ------------------------------------------------------------ */

        function setMode(next) {
            mode = next;
            const registering = mode === "register";
            if (elements.authTitle) elements.authTitle.textContent = registering ? "Create your account" : "Welcome back";
            if (elements.authUsernameField) elements.authUsernameField.hidden = !registering;
            if (elements.authEmailField) elements.authEmailField.hidden = !registering;
            if (elements.authIdentifierField) elements.authIdentifierField.hidden = registering;
            // Confirmation belongs to the form where a typo is unrecoverable.
            // Signing in already tells you immediately that you got it wrong.
            if (elements.authConfirmField) elements.authConfirmField.hidden = !registering;
            if (elements.authSubmit) elements.authSubmit.textContent = registering ? "Create account" : "Sign in";
            if (elements.authSwitch) elements.authSwitch.textContent = registering ? "I already have an account" : "Create an account instead";
            if (elements.authPassword) {
                elements.authPassword.autocomplete = registering ? "new-password" : "current-password";
            }
            if (elements.authConfirm) elements.authConfirm.value = "";
            concealPasswords(elements.authPassword, elements.authConfirm);
            describeAuthIntro(registering);
            setError(null);
        }

        function describeAuthIntro(registering) {
            if (!elements.authIntro) return;
            const midRound = midRoundAsGuest();
            if (registering) {
                elements.authIntro.textContent = midRound
                    ? "Your account starts on a clean board. This round stays saved on this device and comes back when you sign out."
                    : "Keep your board, best score, and streak on every device you play on.";
            } else {
                elements.authIntro.textContent = midRound
                    ? "Signing in loads the round saved to your account. This round stays on this device and comes back when you sign out."
                    : "Sign in to pick up the round you left on another device.";
            }
        }

        /** A guest round the player would notice losing from the screen. */
        function midRoundAsGuest() {
            if (game.getProfile?.() === "account") return false;
            const save = game.getSave?.() ?? null;
            return (save?.score ?? 0) > 0 || (save?.moves ?? 0) > 0;
        }

        /* ------------------------------------------------------------ */
        /* Guest round handover                                          */
        /* ------------------------------------------------------------ */

        /** Resolver for the confirmation currently on screen, if any. */
        let pendingHandover = null;

        function settleHandover(accepted) {
            const resolve = pendingHandover;
            pendingHandover = null;
            if (elements.profileSwitchDialog?.open) elements.profileSwitchDialog.close();
            if (resolve) resolve(accepted);
        }

        /**
         * Asks before a sign-in takes the current board off the screen.
         *
         * Resolves true when there is nothing to lose, when the page has no
         * confirmation markup, or when the player accepts. The guest round is
         * never actually deleted — it is parked — but it does leave the
         * screen, and leaving the screen without warning is what made this
         * feel like data loss.
         */
        function confirmHandover() {
            // Returns `true` — not a resolved promise — when there is nothing
            // to ask, so the common path adds no turn of the event loop
            // between the click and the request.
            if (!midRoundAsGuest()) return true;
            const dialog = elements.profileSwitchDialog;
            if (typeof dialog?.showModal !== "function") return true;
            if (elements.profileSwitchBody) {
                elements.profileSwitchBody.textContent = mode === "register"
                    ? "Your new account starts on a clean board. This round stays saved on this device and comes back the moment you sign out."
                    : "Your account keeps its own board. This round stays saved on this device and comes back the moment you sign out.";
            }
            return new Promise(resolve => {
                pendingHandover = resolve;
                dialog.showModal();
            });
        }

        function openAuth(next) {
            setMode(next);
            if (elements.authDialog) elements.authDialog.showModal();
        }

        function closeAuth() {
            if (elements.authDialog?.open) elements.authDialog.close();
            concealPasswords(elements.authPassword, elements.authConfirm);
            setError(null);
        }

        /* ------------------------------------------------------------ */
        /* Password reset                                                */
        /* ------------------------------------------------------------ */

        function openReset() {
            closeAuth();
            setResetError(null);
            if (elements.resetUsername) {
                elements.resetUsername.value = elements.authIdentifier?.value?.trim()
                    ?? elements.authUsername?.value?.trim()
                    ?? "";
            }
            if (elements.resetEmail) elements.resetEmail.value = elements.authEmail?.value?.trim() ?? "";
            for (const field of [elements.resetPassword, elements.resetConfirm]) {
                if (field) field.value = "";
            }
            concealPasswords(elements.resetPassword, elements.resetConfirm);
            if (elements.resetDialog) elements.resetDialog.showModal();
        }

        function closeReset() {
            if (elements.resetDialog?.open) elements.resetDialog.close();
            for (const field of [elements.resetPassword, elements.resetConfirm]) {
                if (field) field.value = "";
            }
            concealPasswords(elements.resetPassword, elements.resetConfirm);
            setResetError(null);
        }

        async function submitReset(event) {
            if (event?.preventDefault) event.preventDefault();
            if (currentBusy()) return;

            const newPassword = elements.resetPassword?.value ?? "";
            if (newPassword !== (elements.resetConfirm?.value ?? "")) {
                setResetError("Those passwords do not match.");
                elements.resetConfirm?.focus?.();
                return;
            }

            setResetError(null);
            beginBusy("reset");
            try {
                await cloud.resetPassword({
                    username: elements.resetUsername?.value?.trim() ?? "",
                    email: elements.resetEmail?.value?.trim() ?? "",
                    newPassword
                });
                closeReset();
                // A reset signs every device out, this one included, so the
                // player lands back on the form they came from rather than
                // in a session they no longer have.
                if (game.getProfile?.() === "account") game.endAccountSession?.();
                openAuth("login");
                setStatus("Password reset. Sign in with your new password.");
            } catch (error) {
                setResetError(error.message);
            } finally {
                endBusy();
            }
        }

        function openAccount() {
            renderAccountDialog();
            if (elements.accountDialog) elements.accountDialog.showModal();
        }

        async function submitAuth(event) {
            if (event?.preventDefault) event.preventDefault();
            if (currentBusy()) return;
            if (mode === "register" && (elements.authPassword?.value ?? "") !== (elements.authConfirm?.value ?? "")) {
                setError("Those passwords do not match.");
                elements.authConfirm?.focus?.();
                return;
            }

            const handingOver = midRoundAsGuest();
            const decision = confirmHandover();
            if (decision !== true && !(await decision)) return;

            setError(null);
            beginBusy("auth");

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

                for (const field of [elements.authPassword, elements.authConfirm]) {
                    if (field) field.value = "";
                }
                closeAuth();
                cloud.dismissPrompt();
                // The guest round is parked, not uploaded. What the account
                // holds is the only round allowed onto the screen from here.
                game.beginAccountSession?.({ fresh: true });
                // A pull that failed has already put its own reason on screen,
                // and overwriting it with a cheerful confirmation is how a
                // player ends up believing a sync happened that did not.
                if (await adoptAccountRound()) {
                    setStatus(
                        handingOver
                            ? "Signed in. Your guest round is safe on this device and returns when you sign out."
                            : "Signed in. Your account is ready."
                    );
                }
            } catch (error) {
                setError(error.message);
            } finally {
                endBusy();
            }
        }

        async function signOut() {
            if (currentBusy() === "signout") return;
            // Drop any queued upload so a late response cannot reappear after
            // the session is gone.
            scheduleSync.cancel();
            beginBusy("signout");
            try {
                await cloud.logout();
                if (elements.accountDialog) elements.accountDialog.close();
                // Back to the round this device was playing before the session
                // started — board, score, and best score all as they were.
                game.endAccountSession?.();
                setStatus("Signed out. Your device's own round is back.");
            } finally {
                endBusy();
            }
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
            if (currentBusy() === "leaderboard") return;
            renderPeriodButtons();
            if (elements.leaderboardNote) elements.leaderboardNote.textContent = "Loading…";
            beginBusy("leaderboard");
            try {
                renderLeaderboard(await cloud.leaderboard({ period, limit: 20 }));
            } catch (error) {
                renderLeaderboard(null);
                if (elements.leaderboardNote) elements.leaderboardNote.textContent = error.message;
            } finally {
                endBusy();
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
            clearToastTimer();
            toastElapsed = true;
            cloud.dismissPrompt();
            renderBanner();
        });

        listen(elements.authForm, "submit", submitAuth);
        listen(elements.authSwitch, "click", event => {
            if (event?.preventDefault) event.preventDefault();
            setMode(mode === "register" ? "login" : "register");
        });
        listen(elements.authCancel, "click", () => closeAuth());
        listen(elements.authDismiss, "click", () => closeAuth());
        // Backdrop click and Escape both leave the board alone.
        listen(elements.authDialog, "click", event => {
            if (event?.target === elements.authDialog) closeAuth();
        });
        listen(elements.authDialog, "cancel", () => setError(null));

        listen(elements.authForgot, "click", event => {
            if (event?.preventDefault) event.preventDefault();
            openReset();
        });
        listen(elements.resetForm, "submit", submitReset);
        listen(elements.resetCancel, "click", () => {
            closeReset();
            openAuth("login");
        });
        listen(elements.resetDismiss, "click", () => closeReset());
        listen(elements.resetDialog, "click", event => {
            if (event?.target === elements.resetDialog) closeReset();
        });

        for (const button of revealButtons) listen(button, "click", () => toggleReveal(button));

        listen(elements.profileSwitchConfirm, "click", () => settleHandover(true));
        listen(elements.profileSwitchCancel, "click", () => settleHandover(false));
        // Escape and a backdrop click both mean "no" — and both must resolve
        // the promise, or the sign-in button stays dead for the session.
        listen(elements.profileSwitchDialog, "close", () => settleHandover(false));
        listen(elements.profileSwitchDialog, "click", event => {
            if (event?.target === elements.profileSwitchDialog) settleHandover(false);
        });

        listen(elements.accountSyncNow, "click", () => syncNowPreferred());
        listen(elements.accountSignOut, "click", () => signOut());
        listen(elements.accountClose, "click", () => elements.accountDialog?.close());

        listen(elements.leaderboardClose, "click", () => elements.leaderboardDialog?.close());
        listen(elements.leaderboardPeriods, "click", event => {
            const next = event?.target?.dataset?.period;
            if (!next || next === period) return;
            period = next;
            return loadLeaderboard();
        });

        // Flush a pending debounce when the tab hides so a mid-round quit still
        // reaches the account without waiting for Sync now.
        if (typeof document !== "undefined" && typeof document.addEventListener === "function") {
            document.addEventListener("visibilitychange", flushSyncOnHide);
        }

        const unsubscribeCloud = cloud.subscribe(next => {
            state = next;
            if (state.signedIn) {
                clearToastTimer();
                toastElapsed = true;
            }
            render();
        });
        const unsubscribeGame = game.subscribe(onGameChange);

        return {
            /** Restores a session and reconciles, if there is one to restore. */
            async start() {
                setMode("register");
                toastElapsed = false;
                render();
                if (!state.available) return;
                if (!state.signedIn && !cloud.promptDismissed()) scheduleToastHide();
                const restoring = Boolean(cloud.getState().pending);
                // Switch storage before the first frame rather than after the
                // network answers: a stored session must never flash the guest
                // board, and must never let a guest move reach the account.
                let adopted = null;
                if (restoring) {
                    adopted = game.beginAccountSession?.() ?? "fresh";
                    beginBusy("sync");
                }
                try {
                    if (await cloud.restore()) {
                        // A cached account round is this account's own and can
                        // be reconciled. Nothing cached means nothing to offer,
                        // so pull rather than push an empty board over it.
                        await (adopted === "restored" ? syncNow("auto") : adoptAccountRound());
                    } else if (restoring) {
                        game.endAccountSession?.();
                    }
                } finally {
                    if (restoring) endBusy();
                }
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
                clearToastTimer();
                scheduleSync.cancel();
                if (typeof document !== "undefined" && typeof document.removeEventListener === "function") {
                    document.removeEventListener("visibilitychange", flushSyncOnHide);
                }
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
