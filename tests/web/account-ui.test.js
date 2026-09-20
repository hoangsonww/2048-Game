"use strict";

// The account, sync, and leaderboard surface.
//
// The controller is built from injected dependencies — a document, a cloud
// client, and the game bridge — so all of it is reachable without a browser.
// What these tests protect is the product rule behind the feature: an account
// is an invitation, never a gate, and nothing the cloud does may take the
// game away from the player in front of it.

const test = require("node:test");
const assert = require("node:assert/strict");
const { createAccountUI, autoStart } = require("../../Web-Version/account.js");
const { FakeElement } = require("./helpers/fake-dom.js");

const IDS = [
    "accountButton", "accountButtonLabel", "leaderboardButton", "cloudStatus",
    "cloudBanner", "cloudBannerCreate", "cloudBannerSignIn", "cloudBannerDismiss",
    "authDialog", "authForm", "authTitle", "authIntro", "authUsernameField", "authUsername",
    "authEmailField", "authEmail", "authIdentifierField", "authIdentifier", "authPassword",
    "authConfirmField", "authConfirm",
    "authSubmit", "authSwitch", "authForgot", "authDismiss", "authError",
    "resetDialog", "resetForm", "resetUsername", "resetEmail", "resetPassword",
    "resetConfirm", "resetSubmit", "resetCancel", "resetDismiss", "resetError",
    "profileSwitchDialog", "profileSwitchTitle", "profileSwitchBody",
    "profileSwitchConfirm", "profileSwitchCancel",
    "accountDialog", "accountName", "accountEmail", "accountSummary", "accountSync",
    "accountSyncNow", "accountSignOut", "accountClose",
    "leaderboardDialog", "leaderboardPeriods", "leaderboardList", "leaderboardNote", "leaderboardClose"
];

/** The reveal controls, as `index.html` declares them. */
const REVEAL = [
    ["authPassword", "password"],
    ["authConfirm", "confirmation password"],
    ["resetPassword", "new password"],
    ["resetConfirm", "new confirmation password"]
];

function fakePage() {
    const elements = Object.fromEntries(IDS.map(id => [id, new FakeElement()]));
    elements.authError.hidden = true;
    elements.resetError.hidden = true;
    elements.cloudBanner.hidden = true;
    // Password inputs start hidden, which is what the reveal toggle flips.
    for (const [id] of REVEAL) elements[id].type = "password";

    for (const period of ["daily", "weekly", "all"]) {
        const button = new FakeElement("button");
        button.className = "period-button";
        button.dataset.period = period;
        elements.leaderboardPeriods.appendChild(button);
    }

    const revealButtons = REVEAL.map(([target, label]) => {
        const button = new FakeElement("button");
        button.setAttribute("data-reveal", target);
        button.setAttribute("data-reveal-label", label);
        button.setAttribute("aria-pressed", "false");
        button.setAttribute("aria-label", `Show ${label}`);
        return button;
    });

    return {
        elements,
        reveal: Object.fromEntries(REVEAL.map(([target], index) => [target, revealButtons[index]])),
        document: {
            getElementById: id => elements[id] ?? null,
            querySelectorAll: selector => (selector === "[data-reveal]" ? revealButtons : []),
            createElement: tag => new FakeElement(tag),
            visibilityState: "visible",
            _listeners: new Map(),
            addEventListener(type, handler) {
                if (!this._listeners.has(type)) this._listeners.set(type, new Set());
                this._listeners.get(type).add(handler);
            },
            removeEventListener(type, handler) {
                this._listeners.get(type)?.delete(handler);
            },
            dispatch(type) {
                for (const handler of this._listeners.get(type) ?? []) handler();
            }
        }
    };
}

/** A cloud client stand-in that records calls and can be told how to answer. */
function fakeCloud(overrides = {}) {
    const listeners = new Set();
    const calls = [];
    let state = {
        available: true,
        signedIn: false,
        pending: false,
        user: null,
        lastSync: null,
        lastResolution: null,
        lastError: null,
        deviceId: "web-test"
    };
    let dismissed = false;

    const cloud = {
        calls,
        setState(next) {
            state = { ...state, ...next };
            for (const listener of listeners) listener(state);
        },
        getState: () => state,
        isSignedIn: () => state.signedIn,
        subscribe(listener) {
            listeners.add(listener);
            listener(state);
            return () => listeners.delete(listener);
        },
        promptDismissed: () => dismissed,
        dismissPrompt() {
            dismissed = true;
            calls.push(["dismissPrompt"]);
        },
        async restore() {
            calls.push(["restore"]);
            return overrides.restore ? overrides.restore(cloud) : null;
        },
        async register(payload) {
            calls.push(["register", payload]);
            if (overrides.register) return overrides.register(cloud, payload);
            cloud.setState({ signedIn: true, user: { username: payload.username, displayName: payload.username, email: payload.email, statistics: {} } });
            return state.user;
        },
        async login(payload) {
            calls.push(["login", payload]);
            if (overrides.login) return overrides.login(cloud, payload);
            cloud.setState({ signedIn: true, user: { username: "ada", displayName: "Ada", email: "ada@example.test", statistics: {} } });
            return state.user;
        },
        async logout() {
            calls.push(["logout"]);
            cloud.setState({ signedIn: false, user: null });
        },
        async sync(save, strategy) {
            calls.push(["sync", save, strategy]);
            return overrides.sync ? overrides.sync(cloud, save, strategy) : { resolution: "uploaded", save: null };
        },
        async refreshUser() {
            calls.push(["refreshUser"]);
            if (overrides.refreshUser) return overrides.refreshUser(cloud);
            return state.user;
        },
        async submitScore(round) {
            calls.push(["submitScore", round]);
            if (overrides.submitScore) return overrides.submitScore(cloud, round);
            return { score: {} };
        },
        async resetPassword(payload) {
            calls.push(["resetPassword", payload]);
            if (overrides.resetPassword) return overrides.resetPassword(cloud, payload);
            cloud.setState({ signedIn: false, user: null });
            return { reset: true, sessionsRevoked: 1 };
        },
        async leaderboard(params) {
            calls.push(["leaderboard", params]);
            if (overrides.leaderboard) return overrides.leaderboard(cloud, params);
            return { entries: [], summary: { players: 0, topScore: 0 } };
        }
    };

    return cloud;
}

/** The `window.Game2048Game` bridge, reduced to what the UI actually uses. */
function fakeGame(save = { board: new Array(16).fill(0), score: 0, moves: 0, elapsedSeconds: 0 }, options = {}) {
    const listeners = new Set();
    const blank = { board: new Array(16).fill(0), score: 0, moves: 0, elapsedSeconds: 0, bestScore: 0 };
    return {
        applied: [],
        sessions: [],
        profile: "guest",
        cachedAccountRound: options.cachedAccountRound ?? null,
        current: save,
        guestRound: save,
        getSave() { return this.current; },
        getProfile() { return this.profile; },
        hasProgress() { return (this.current?.score ?? 0) > 0 || (this.current?.moves ?? 0) > 0; },
        applySave(next) {
            this.applied.push(next);
            this.current = next;
            return true;
        },
        beginAccountSession(opts) {
            this.sessions.push(["begin", opts ?? null]);
            if (this.profile === "account") return "active";
            this.guestRound = this.current;
            this.profile = "account";
            const cached = opts?.fresh ? null : this.cachedAccountRound;
            this.current = cached ?? { ...blank };
            return cached ? "restored" : "fresh";
        },
        endAccountSession() {
            this.sessions.push(["end", null]);
            if (this.profile !== "account") return false;
            this.profile = "guest";
            this.current = this.guestRound;
            return true;
        },
        subscribe(listener) {
            listeners.add(listener);
            listener("subscribed", this.current);
            return () => listeners.delete(listener);
        },
        emit(reason, next) {
            for (const listener of listeners) listener(reason, next ?? this.current);
        }
    };
}

/** Lets every already-queued promise settle before the next assertion. */
const tick = () => new Promise(resolve => setImmediate(resolve));

/** A controllable clock, so a debounce / toast hide is observable without waiting. */
function fakeTimers() {
    const pending = new Map();
    let nextId = 1;
    let now = 0;
    return {
        setTimeout(run, delay = 0) {
            const id = nextId++;
            pending.set(id, { run, due: now + delay });
            return id;
        },
        clearTimeout(id) { pending.delete(id); },
        pendingCount: () => pending.size,
        advance(ms = 0) {
            now += ms;
            const due = [...pending.entries()].filter(([, entry]) => entry.due <= now);
            for (const [id, entry] of due) {
                pending.delete(id);
                entry.run();
            }
        },
        flush() {
            const runs = [...pending.values()].map(entry => entry.run);
            pending.clear();
            for (const run of runs) run();
        }
    };
}

function mount(options = {}) {
    const page = fakePage();
    const cloud = options.cloud ?? fakeCloud();
    const game = options.game ?? fakeGame();
    const timers = fakeTimers();
    const ui = createAccountUI({
        document: page.document,
        cloud,
        game,
        setTimeout: timers.setTimeout,
        clearTimeout: timers.clearTimeout,
        syncDelay: 10,
        toastDuration: options.toastDuration ?? 5500
    });
    return { ...page, cloud, game, timers, ui };
}

/* ---------------------------------------------------------------------- */

test("a signed-out player is invited with a temporary toast, not blocked", async () => {
    const app = mount();
    await app.ui.start();

    assert.equal(app.elements.cloudBanner.hidden, false, "the invitation is visible on load");
    assert.equal(app.elements.accountButtonLabel.textContent, "Sign in");
    assert.match(app.elements.cloudStatus.textContent, /saved locally/);

    app.timers.advance(5500);
    assert.equal(app.elements.cloudBanner.hidden, true, "the toast auto-hides without permanently dismissing");
    assert.equal(app.cloud.promptDismissed(), false, "auto-hide is session-only; Sign in remains available");
});

test("dismissing the invitation hides it and remembers the choice", async () => {
    const app = mount();
    await app.ui.start();

    app.elements.cloudBannerDismiss.dispatch("click");

    assert.equal(app.elements.cloudBanner.hidden, true);
    assert.equal(app.cloud.promptDismissed(), true);
});

test("the invitation stays hidden when the browser cannot reach the cloud", async () => {
    const cloud = fakeCloud();
    cloud.setState({ available: false });
    const app = mount({ cloud });

    await app.ui.start();

    assert.equal(app.elements.cloudBanner.hidden, true, "offering an account that cannot be created is worse than offering nothing");
    assert.match(app.elements.cloudStatus.textContent, /Offline play only/);
    assert.equal(app.cloud.calls.some(call => call[0] === "restore"), false, "there is nothing to restore against");
});

test("the account button opens sign-up when signed out and the account panel when signed in", async () => {
    const app = mount();
    await app.ui.start();

    app.elements.accountButton.dispatch("click");
    assert.equal(app.elements.authDialog.open, true);
    assert.equal(app.elements.authTitle.textContent, "Create your account");

    app.elements.authDialog.close();
    app.cloud.setState({ signedIn: true, user: { username: "ada", displayName: "Ada", email: "ada@example.test", statistics: { bestScore: 900, gamesPlayed: 12, highestTile: 256 } } });

    app.elements.accountButton.dispatch("click");
    assert.equal(app.elements.accountDialog.open, true);
    assert.equal(app.elements.accountName.textContent, "Ada");
    assert.match(app.elements.accountSummary.textContent, /Best 900 · 12 rounds · highest tile 256/);
});

test("switching modes swaps the fields rather than opening a second dialog", async () => {
    const app = mount();
    await app.ui.start();
    app.elements.cloudBannerSignIn.dispatch("click");

    assert.equal(app.elements.authTitle.textContent, "Welcome back");
    assert.equal(app.elements.authIdentifierField.hidden, false);
    assert.equal(app.elements.authUsernameField.hidden, true);
    assert.equal(app.elements.authEmailField.hidden, true);

    app.elements.authSwitch.dispatch("click", { preventDefault() {} });

    assert.equal(app.elements.authTitle.textContent, "Create your account");
    assert.equal(app.elements.authUsernameField.hidden, false);
    assert.equal(app.elements.authIdentifierField.hidden, true);
});

test("creating an account signs in, closes the dialog, and reconciles immediately", async () => {
    const app = mount();
    await app.ui.start();

    app.elements.cloudBannerCreate.dispatch("click");
    app.elements.authUsername.value = "  ada  ";
    app.elements.authEmail.value = "ada@example.test";
    app.elements.authPassword.value = "Password1";
    app.elements.authConfirm.value = "Password1";

    await app.elements.authForm.dispatch("submit", { preventDefault() {} });

    const register = app.cloud.calls.find(call => call[0] === "register");
    assert.equal(register[1].username, "ada", "whitespace a player typed is not part of their username");
    assert.equal(app.elements.authDialog.open, false);
    assert.equal(app.elements.authPassword.value, "", "the password is cleared from the form");
    assert.equal(app.elements.cloudBanner.hidden, true);
    // Signing in is when the two sides are most likely to disagree, so it runs
    // a full reconciliation rather than a debounced upload.
    assert.ok(app.cloud.calls.some(call => call[0] === "sync"));
});

test("a rejected sign-in shows the reason and keeps the dialog open", async () => {
    const cloud = fakeCloud({
        login() {
            const error = new Error("That email or password is not correct.");
            error.code = "invalid_credentials";
            throw error;
        }
    });
    const app = mount({ cloud });
    await app.ui.start();

    app.elements.cloudBannerSignIn.dispatch("click");
    app.elements.authIdentifier.value = "ada";
    app.elements.authPassword.value = "wrong";
    await app.elements.authForm.dispatch("submit", { preventDefault() {} });

    assert.equal(app.elements.authError.hidden, false);
    assert.match(app.elements.authError.textContent, /not correct/);
    assert.equal(app.elements.authDialog.open, true, "a player who mistyped should not have to reopen the form");
});

test("the submit button is re-enabled after a failure", async () => {
    const cloud = fakeCloud({ register() { throw new Error("nope"); } });
    const app = mount({ cloud });
    await app.ui.start();

    app.elements.accountButton.dispatch("click");
    await app.elements.authForm.dispatch("submit", { preventDefault() {} });

    assert.equal(app.elements.authSubmit.disabled, false);
    assert.equal(app.elements.authSubmit.textContent, "Create account");
});

test("auth submit shows a loading state until the request finishes", async () => {
    let release;
    const held = new Promise(resolve => { release = resolve; });
    const cloud = fakeCloud({ register() { return held; } });
    const app = mount({ cloud });
    await app.ui.start();

    app.elements.accountButton.dispatch("click");
    app.elements.authForm.dispatch("submit", { preventDefault() {} });
    app.elements.authForm.dispatch("submit", { preventDefault() {} });
    assert.equal(app.cloud.calls.filter(call => call[0] === "register").length, 1);

    assert.equal(app.elements.authSubmit.disabled, true);
    assert.equal(app.elements.authSubmit.textContent, "Creating account…");
    assert.equal(app.elements.authSubmit.classList.contains("is-busy"), true);
    assert.equal(app.elements.authForm.getAttribute("aria-busy"), "true");
    assert.equal(app.elements.authUsername.disabled, true);
    assert.match(app.elements.cloudStatus.textContent, /Creating account/);

    release();
    await tick();
    await tick();

    assert.equal(app.elements.authSubmit.disabled, false);
    assert.equal(app.elements.authDialog.open, false);
});

test("Sync now and the leaderboard show loading copy while the request is in flight", async () => {
    let releaseSync;
    const heldSync = new Promise(resolve => { releaseSync = resolve; });
    const cloud = fakeCloud({
        sync() { return heldSync; },
        leaderboard() { return new Promise(() => {}); }
    });
    const app = mount({ cloud });
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });

    const syncing = app.ui.syncNow();
    assert.equal(app.elements.accountSyncNow.disabled, true);
    assert.equal(app.elements.accountSyncNow.textContent, "Syncing…");
    assert.equal(app.elements.accountSyncNow.classList.contains("is-busy"), true);
    assert.match(app.elements.cloudStatus.textContent, /Syncing/);
    assert.equal(await app.ui.syncNow(), null, "a second Sync now must not stack another request");
    releaseSync({ resolution: "uploaded", save: null });
    await syncing;
    assert.equal(app.elements.accountSyncNow.disabled, false);
    assert.equal(app.elements.accountSyncNow.textContent, "Sync now");

    app.ui.openLeaderboard();
    app.ui.openLeaderboard();
    assert.equal(app.cloud.calls.filter(call => call[0] === "leaderboard").length, 1, "period clicks during load must not stack");
    assert.equal(app.elements.leaderboardNote.textContent, "Loading…");
    assert.equal(app.elements.leaderboardNote.classList.contains("is-busy"), true);
    assert.equal(app.elements.leaderboardDialog.getAttribute("aria-busy"), "true");
    assert.equal(app.elements.leaderboardPeriods.children.every(button => button.disabled), true);
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
});

test("sign-in and sign-out also show loading copy while the request is in flight", async () => {
    let releaseLogin;
    const heldLogin = new Promise(resolve => { releaseLogin = resolve; });
    let releaseLogout;
    const heldLogout = new Promise(resolve => { releaseLogout = resolve; });
    const cloud = fakeCloud({
        login() { return heldLogin; },
        logout() { return heldLogout; }
    });
    const app = mount({ cloud });
    await app.ui.start();

    app.elements.cloudBannerSignIn.dispatch("click");
    app.elements.authForm.dispatch("submit", { preventDefault() {} });
    assert.equal(app.elements.authSubmit.textContent, "Signing in…");
    assert.match(app.elements.cloudStatus.textContent, /Signing in/);
    releaseLogin();
    await tick();
    await tick();

    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
    app.elements.accountSignOut.dispatch("click");
    app.elements.accountSignOut.dispatch("click");
    assert.equal(app.cloud.calls.filter(call => call[0] === "logout").length, 1);
    assert.equal(app.elements.accountSignOut.disabled, true);
    assert.equal(app.elements.accountSignOut.textContent, "Signing out…");
    releaseLogout();
    await tick();
    await tick();
    assert.equal(app.elements.accountSignOut.textContent, "Sign out");
});

test("restoring a stored session shows a syncing status", async () => {
    let release;
    const held = new Promise(resolve => { release = resolve; });
    const cloud = fakeCloud({ restore() { return held; } });
    const app = mount({ cloud });
    app.cloud.setState({ pending: true });

    const starting = app.ui.start();
    assert.match(app.elements.cloudStatus.textContent, /Syncing/);
    assert.equal(app.elements.cloudStatus.classList.contains("is-busy"), true);
    release(null);
    await starting;
    assert.equal(app.elements.cloudStatus.classList.contains("is-busy"), false);
});

test("the dismiss control and backdrop click both close the auth dialog", async () => {
    // The close icon is the only dismiss control the form carries; a second
    // "not now" button underneath the submit said the same thing twice.
    const app = mount();
    await app.ui.start();

    app.elements.accountButton.dispatch("click");
    assert.equal(app.elements.authDialog.open, true);
    app.elements.authDismiss.dispatch("click");
    assert.equal(app.elements.authDialog.open, false);
    assert.equal(app.cloud.isSignedIn(), false, "dismissing changes nothing");

    app.elements.accountButton.dispatch("click");
    app.elements.authDialog.dispatch("click", { target: app.elements.authDialog });
    assert.equal(app.elements.authDialog.open, false);
});

test("a downloaded round replaces the board; an upload leaves it alone", async () => {
    const remote = { board: new Array(16).fill(0), score: 500, moves: 40 };
    const cloud = fakeCloud({ sync: () => ({ resolution: "downloaded", save: remote }) });
    const app = mount({ cloud });
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });

    await app.ui.syncNow();
    assert.deepEqual(app.game.applied, [remote]);

    const uploader = mount({ cloud: fakeCloud({ sync: () => ({ resolution: "uploaded", save: { score: 1 } }) }) });
    uploader.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
    await uploader.ui.syncNow();
    assert.deepEqual(uploader.game.applied, [], "the device that sent the round is already showing it");
});

test("a conflict is explained in the player's own words", async () => {
    const cloud = fakeCloud();
    const app = mount({ cloud });
    app.cloud.setState({
        signedIn: true,
        user: { username: "ada", statistics: {} },
        lastResolution: "conflicted"
    });

    assert.match(app.elements.cloudStatus.textContent, /the further one was kept, and the other is safe/);
});

test("a failed sync reports itself and does not throw", async () => {
    const cloud = fakeCloud({
        sync() { throw new Error("Could not reach the 2048 cloud."); }
    });
    const app = mount({ cloud });
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });

    const result = await app.ui.syncNow();

    assert.equal(result, null);
    assert.match(app.elements.cloudStatus.textContent, /Could not reach/);
});

test("syncing while signed out is a no-op", async () => {
    const app = mount();
    assert.equal(await app.ui.syncNow(), null);
    assert.equal(app.cloud.calls.some(call => call[0] === "sync"), false);
});

test("moves are synced on a debounce rather than one request each", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });

    app.game.emit("move");
    app.game.emit("move");
    app.game.emit("move");

    assert.equal(app.cloud.calls.filter(call => call[0] === "sync").length, 0, "nothing is sent mid-burst");
    app.timers.flush();
    await Promise.resolve();
    assert.equal(app.cloud.calls.filter(call => call[0] === "sync").length, 1, "three moves cost one request");
});

test("a finished round is submitted to the leaderboard and synced at once", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });

    const finished = { board: new Array(16).fill(2), score: 4000, moves: 300, elapsedSeconds: 600 };
    app.game.emit("game-over", finished);
    await Promise.resolve();

    const submitted = app.cloud.calls.find(call => call[0] === "submitScore");
    assert.ok(submitted, "the round should be submitted");
    assert.equal(submitted[1].score, 4000);
    assert.equal(submitted[1].durationSeconds, 600);
    assert.equal(app.timers.pendingCount(), 0, "the end of a round is not a moment to debounce");
});

test("a scoreless round is not submitted", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });

    app.game.emit("game-over", { board: new Array(16).fill(0), score: 0, moves: 0, elapsedSeconds: 3 });
    await Promise.resolve();

    assert.equal(app.cloud.calls.some(call => call[0] === "submitScore"), false);
});

test("a failed submission is swallowed rather than shown as an error", async () => {
    const cloud = fakeCloud({ submitScore() { throw new Error("offline"); } });
    const app = mount({ cloud });
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });

    app.game.emit("game-over", { board: new Array(16).fill(2), score: 100, moves: 10, elapsedSeconds: 30 });
    await Promise.resolve();
    await Promise.resolve();

    // The score is already on the player's screen and in local storage. A
    // leaderboard round trip that failed is not their problem to action.
    assert.doesNotThrow(() => app.elements.cloudStatus.textContent);
});

test("a round restored by a sync does not trigger another sync", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });

    app.game.emit("restored");

    assert.equal(app.timers.pendingCount(), 0, "re-syncing what we just downloaded is a round trip that says nothing");
});

test("a signed-out player's moves are not sent anywhere", () => {
    const app = mount();
    app.game.emit("move");
    assert.equal(app.timers.pendingCount(), 0);
    assert.equal(app.cloud.calls.some(call => call[0] === "sync"), false);
});

test("the leaderboard renders ranked rows and marks the viewer", async () => {
    const cloud = fakeCloud({
        leaderboard: () => ({
            entries: [
                { rank: 1, username: "ada", displayName: "Ada", score: 9000, highestTile: 2048, isViewer: false },
                { rank: 2, username: "bob", displayName: "", score: 8000, highestTile: 1024, isViewer: true }
            ],
            summary: { players: 2, topScore: 9000 }
        })
    });
    const app = mount({ cloud });

    await app.ui.openLeaderboard();

    assert.equal(app.elements.leaderboardDialog.open, true);
    const rows = app.elements.leaderboardList.children;
    assert.equal(rows.length, 2);
    assert.equal(rows[0].children[1].textContent, "Ada");
    assert.equal(rows[1].children[1].textContent, "bob", "a player with no display name is shown by username");
    assert.equal(rows[1].classList.contains("leaderboard-row--you"), true);
    assert.match(app.elements.leaderboardNote.textContent, /2 players · top score 9,000/);
});

test("an empty window says so instead of showing a blank list", async () => {
    const app = mount();
    await app.ui.openLeaderboard();

    assert.equal(app.elements.leaderboardList.children.length, 0);
    assert.match(app.elements.leaderboardNote.textContent, /No rounds in this window yet/);
});

test("a failed leaderboard read shows the reason", async () => {
    const cloud = fakeCloud({ leaderboard() { throw new Error("Could not reach the 2048 cloud."); } });
    const app = mount({ cloud });

    await app.ui.openLeaderboard();

    assert.match(app.elements.leaderboardNote.textContent, /Could not reach/);
});

test("choosing a window reloads the board and marks the active button", async () => {
    const app = mount();
    await app.ui.openLeaderboard();
    app.cloud.calls.length = 0;

    const weekly = app.elements.leaderboardPeriods.children.find(button => button.dataset.period === "weekly");
    await app.elements.leaderboardPeriods.dispatch("click", { target: weekly });

    assert.equal(app.cloud.calls.find(call => call[0] === "leaderboard")[1].period, "weekly");
    assert.equal(weekly.getAttribute("aria-pressed"), "true");
    assert.equal(app.elements.leaderboardPeriods.children.find(button => button.dataset.period === "all").getAttribute("aria-pressed"), "false");
});

test("clicking the active window or the empty space does not refetch", async () => {
    const app = mount();
    await app.ui.openLeaderboard();
    app.cloud.calls.length = 0;

    const all = app.elements.leaderboardPeriods.children.find(button => button.dataset.period === "all");
    await app.elements.leaderboardPeriods.dispatch("click", { target: all });
    await app.elements.leaderboardPeriods.dispatch("click", { target: { dataset: {} } });
    await app.elements.leaderboardPeriods.dispatch("click", {});

    assert.equal(app.cloud.calls.length, 0);
});

test("the leaderboard button and close button work", async () => {
    const app = mount();
    await app.elements.leaderboardButton.dispatch("click");
    assert.equal(app.elements.leaderboardDialog.open, true);

    app.elements.leaderboardClose.dispatch("click");
    assert.equal(app.elements.leaderboardDialog.open, false);
});

test("setPeriod is available for callers that are not a click", async () => {
    const app = mount();
    await app.ui.setPeriod("daily");
    assert.equal(app.cloud.calls.find(call => call[0] === "leaderboard")[1].period, "daily");
});

test("signing out closes the panel and reassures the player about their round", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
    app.elements.accountButton.dispatch("click");

    await app.elements.accountSignOut.dispatch("click");

    assert.equal(app.elements.accountDialog.open, false);
    assert.match(app.elements.cloudStatus.textContent, /own round is back/);
    assert.deepEqual(app.game.sessions, [["end", null]], "signing out hands the device back its own round");
});

test("sync now and done are wired", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
    app.elements.accountButton.dispatch("click");

    await app.elements.accountSyncNow.dispatch("click");
    const syncCall = app.cloud.calls.find(call => call[0] === "sync");
    assert.ok(syncCall, "Sync now must hit the cloud");
    assert.equal(syncCall[2], "prefer-local", "Sync now pushes this device's board");

    app.elements.accountClose.dispatch("click");
    assert.equal(app.elements.accountDialog.open, false);
});

test("career totals come from the account and never from the device", async () => {
    // The bug this replaces: a brand-new account showed "Best 1,200 · 0
    // rounds · highest tile 128" because the panel folded in the guest round
    // sitting in localStorage. An account that has played nothing has played
    // nothing.
    const app = mount({
        game: fakeGame({ board: new Array(16).fill(0).map((_, i) => (i === 0 ? 128 : 0)), score: 400, bestScore: 1200, moves: 40 })
    });
    app.cloud.setState({ signedIn: true, user: { username: "ada", displayName: "Ada", email: "a@b.test", statistics: { bestScore: 0, gamesPlayed: 0, highestTile: 0 } } });
    app.elements.accountButton.dispatch("click");

    assert.equal(app.elements.accountSummary.textContent, "Best 0 · 0 rounds · highest tile 0");
});

test("career totals render the account's own figures", async () => {
    const app = mount();
    app.cloud.setState({
        signedIn: true,
        user: { username: "ada", displayName: "Ada", email: "a@b.test", statistics: { bestScore: 9100, gamesPlayed: 31, highestTile: 1024 } }
    });
    app.elements.accountButton.dispatch("click");

    assert.equal(app.elements.accountSummary.textContent, "Best 9,100 · 31 rounds · highest tile 1,024");
});

test("signing in mid-round asks first, then hands the round over", async () => {
    const remote = { board: new Array(16).fill(0).map((_, i) => (i === 0 ? 8 : 0)), score: 24, moves: 3, revision: 4 };
    const cloud = fakeCloud({ sync: () => ({ resolution: "downloaded", save: remote }) });
    const app = mount({
        cloud,
        game: fakeGame({ board: new Array(16).fill(2), score: 80, bestScore: 80, moves: 12 })
    });
    await app.ui.start();
    app.elements.accountButton.dispatch("click");
    assert.match(app.elements.authIntro.textContent, /comes back when you sign out/i);

    const submitted = app.elements.authForm.dispatch("submit", { preventDefault() {} });
    await tick();
    // Nothing has been sent yet: the player has been asked, not signed in.
    assert.equal(app.elements.profileSwitchDialog.open, true);
    assert.equal(app.cloud.calls.some(call => call[0] === "register"), false);

    app.elements.profileSwitchConfirm.dispatch("click");
    await submitted;
    await tick();

    assert.equal(app.elements.profileSwitchDialog.open, false);
    assert.deepEqual(app.game.sessions, [["begin", { fresh: true }]]);
    const syncCall = app.cloud.calls.find(call => call[0] === "sync");
    assert.equal(syncCall[1], null, "the guest round is never offered to the account");
    assert.deepEqual(app.game.applied, [remote]);
    assert.match(app.elements.cloudStatus.textContent, /guest round is safe/);
});

test("declining the handover leaves the player exactly where they were", async () => {
    const app = mount({
        game: fakeGame({ board: new Array(16).fill(2), score: 80, bestScore: 80, moves: 12 })
    });
    await app.ui.start();
    app.elements.accountButton.dispatch("click");

    const submitted = app.elements.authForm.dispatch("submit", { preventDefault() {} });
    await tick();
    app.elements.profileSwitchCancel.dispatch("click");
    await submitted;
    await tick();

    assert.equal(app.cloud.calls.some(call => call[0] === "register"), false);
    assert.deepEqual(app.game.sessions, []);
    assert.equal(app.game.current.score, 80);
    assert.equal(app.elements.authDialog.open, true, "the form stays up so they can change their mind");
});

test("dismissing the handover dialog counts as declining", async () => {
    const app = mount({
        game: fakeGame({ board: new Array(16).fill(2), score: 80, bestScore: 80, moves: 12 })
    });
    await app.ui.start();
    app.elements.accountButton.dispatch("click");

    const submitted = app.elements.authForm.dispatch("submit", { preventDefault() {} });
    await tick();
    // Escape closes a <dialog> without any button being pressed.
    app.elements.profileSwitchDialog.close();
    await submitted;
    await tick();

    assert.equal(app.cloud.calls.some(call => call[0] === "register"), false);
    assert.deepEqual(app.game.sessions, []);

    // And a backdrop click is the same answer.
    const again = app.elements.authForm.dispatch("submit", { preventDefault() {} });
    await tick();
    app.elements.profileSwitchDialog.dispatch("click", { target: app.elements.profileSwitchDialog });
    await again;
    await tick();
    assert.deepEqual(app.game.sessions, []);
});

test("signing in with an untouched board needs no confirmation", async () => {
    const app = mount();
    await app.ui.start();
    app.elements.accountButton.dispatch("click");
    assert.match(app.elements.authIntro.textContent, /every device/i);

    await app.elements.authForm.dispatch("submit", { preventDefault() {} });
    await tick();

    assert.equal(app.elements.profileSwitchDialog.open, false);
    assert.deepEqual(app.game.sessions, [["begin", { fresh: true }]]);
    assert.match(app.elements.cloudStatus.textContent, /account is ready/);
});

test("signing out cancels a pending auto-sync and restores the guest round", async () => {
    const app = mount({
        game: fakeGame({ board: new Array(16).fill(4), score: 64, bestScore: 64, moves: 8 })
    });
    app.game.beginAccountSession({ fresh: true });
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
    app.game.emit("move");
    assert.equal(app.timers.pendingCount(), 1);

    await app.elements.accountSignOut.dispatch("click");

    assert.equal(app.timers.pendingCount(), 0);
    assert.equal(app.game.profile, "guest");
    assert.equal(app.game.current.score, 64, "the guest round is exactly as it was left");
    assert.match(app.elements.cloudStatus.textContent, /own round is back/);
});

test("a remote-winning conflict replaces the board", async () => {
    const remote = { board: new Array(16).fill(0), score: 900, moves: 100 };
    const cloud = fakeCloud({
        sync: () => ({ resolution: "conflicted", winner: "remote", save: remote })
    });
    const app = mount({ cloud });
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });

    await app.ui.syncNow("auto");
    assert.deepEqual(app.game.applied, [remote]);
});

test("sync now refreshes the profile and tolerates a refresh failure", async () => {
    let refreshed = 0;
    const cloud = fakeCloud({
        sync: () => ({ resolution: "uploaded", save: { score: 10, bestScore: 40, revision: 2 } }),
        refreshUser(client) {
            refreshed += 1;
            if (refreshed === 1) {
                client.setState({
                    user: { username: "ada", displayName: "Ada", email: "a@b.test", statistics: { bestScore: 40, gamesPlayed: 2, highestTile: 16 } }
                });
                return client.getState().user;
            }
            throw new Error("offline");
        }
    });
    const app = mount({
        cloud,
        game: fakeGame({ board: new Array(16).fill(0), score: 10, bestScore: 40, moves: 3 })
    });
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: { bestScore: 0, gamesPlayed: 0, highestTile: 0 } } });

    await app.ui.syncNow("prefer-local");
    assert.equal(refreshed, 1);
    assert.match(app.elements.accountSummary.textContent, /Best 40/);

    await app.ui.syncNow("prefer-local");
    assert.equal(refreshed, 2, "a failed refresh must not break Sync now");
});

test("hiding the tab flushes a pending auto-sync", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
    app.game.emit("move");
    assert.equal(app.timers.pendingCount(), 1);

    app.document.visibilityState = "hidden";
    app.document.dispatch("visibilitychange");
    await tick();

    assert.equal(app.timers.pendingCount(), 0);
    assert.ok(app.cloud.calls.some(call => call[0] === "sync"));
});

test("a visibility change while the tab is still visible leaves the debounce alone", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
    app.game.emit("move");
    assert.equal(app.timers.pendingCount(), 1);

    app.document.visibilityState = "visible";
    app.document.dispatch("visibilitychange");
    await tick();

    assert.equal(app.timers.pendingCount(), 1, "still-visible tabs must not flush early");
    assert.equal(app.cloud.calls.filter(call => call[0] === "sync").length, 0);
});

test("the account panel reports when the round was last synced", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
    app.elements.accountButton.dispatch("click");
    assert.match(app.elements.accountSync.textContent, /Not synced yet/);

    app.cloud.setState({ lastSync: new Date("2026-09-18T12:00:00Z").toISOString() });
    app.elements.accountButton.dispatch("click");
    assert.match(app.elements.accountSync.textContent, /Last synced/);
});

test("start restores a stored session and reconciles", async () => {
    const cloud = fakeCloud({
        restore(client) {
            client.setState({ signedIn: true, user: { username: "ada", displayName: "Ada", email: "a@b.test", statistics: {} } });
            return client.getState().user;
        }
    });
    const app = mount({ cloud });

    await app.ui.start();

    assert.deepEqual(app.cloud.calls.map(call => call[0]), ["restore", "sync", "refreshUser"]);
    assert.equal(app.elements.accountButtonLabel.textContent, "Ada");
});

test("start with nothing to restore makes no sync request", async () => {
    const app = mount();
    await app.ui.start();
    assert.deepEqual(app.cloud.calls.map(call => call[0]), ["restore"]);
});

test("destroy unsubscribes and cancels any pending sync", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
    app.game.emit("move");
    assert.equal(app.timers.pendingCount(), 1);

    app.ui.destroy();

    assert.equal(app.timers.pendingCount(), 0);
    app.game.emit("move");
    app.cloud.setState({ lastResolution: "uploaded" });
    assert.equal(app.timers.pendingCount(), 0, "a destroyed controller schedules nothing");
});

test("the controller degrades to a no-op on a page with none of its markup", async () => {
    // Every element lookup is guarded because this surface is optional. A page
    // that ships the scripts but not the markup — a stripped embed, a partial
    // template — must lose the feature, never the game.
    const cloud = fakeCloud({
        leaderboard: () => ({ entries: [{ rank: 1, username: "ada", displayName: "Ada", score: 10, highestTile: 4, isViewer: true }], summary: { players: 1, topScore: 10 } })
    });
    const game = fakeGame();
    const timers = fakeTimers();
    const ui = createAccountUI({
        document: { getElementById: () => null, createElement: tag => new FakeElement(tag) },
        cloud,
        game,
        setTimeout: timers.setTimeout,
        clearTimeout: timers.clearTimeout
    });

    await assert.doesNotReject(async () => {
        await ui.start();
        ui.openAuth("login");
        ui.openAuth("register");
        ui.openAccount();
        cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} }, lastSync: new Date().toISOString(), lastResolution: "in_sync" });
        ui.openAccount();
        await ui.openLeaderboard();
        await ui.setPeriod("daily");
        await ui.syncNow();
        game.emit("move");
        timers.flush();
        ui.destroy();
    });
});

test("a submitted form with no inputs sends empty strings rather than undefined", async () => {
    const cloud = fakeCloud();
    const game = fakeGame();
    const timers = fakeTimers();
    const page = fakePage();
    // The two credential inputs are removed; everything else stays.
    const bare = {
        getElementById: id => (id === "authIdentifier" || id === "authPassword" || id === "authUsername" || id === "authEmail" ? null : page.elements[id] ?? null),
        createElement: tag => new FakeElement(tag)
    };
    const ui = createAccountUI({ document: bare, cloud, game, setTimeout: timers.setTimeout, clearTimeout: timers.clearTimeout });

    await ui.start();
    page.elements.authForm.dispatch("submit", { preventDefault() {} });
    // The handler is async and the dispatcher returns the event, not the
    // promise, so the in-flight guard has to be given a turn to clear.
    await tick();
    ui.openAuth("login");
    page.elements.authForm.dispatch("submit", { preventDefault() {} });
    await tick();

    assert.deepEqual(cloud.calls.find(call => call[0] === "register")[1], { username: "", email: "", password: "" });
    assert.deepEqual(cloud.calls.find(call => call[0] === "login")[1], { identifier: "", password: "" });
});

test("a second submit while one is in flight is ignored", async () => {
    let resolveRegister;
    const cloud = fakeCloud({
        register: () => new Promise(resolve => { resolveRegister = resolve; })
    });
    const app = mount({ cloud });
    await app.ui.start();
    app.elements.accountButton.dispatch("click");

    const first = app.elements.authForm.dispatch("submit", { preventDefault() {} });
    app.elements.authForm.dispatch("submit", { preventDefault() {} });

    assert.equal(app.cloud.calls.filter(call => call[0] === "register").length, 1, "double-clicking must not create two accounts");
    resolveRegister({ username: "ada" });
    await first;
});

test("a submit event without preventDefault is still handled", async () => {
    const app = mount();
    await app.ui.start();

    assert.doesNotThrow(() => app.elements.authForm.dispatch("submit", {}));
    await tick();

    assert.ok(app.cloud.calls.some(call => call[0] === "register"));
});

/* --- autoStart ---------------------------------------------------------- */

test("autoStart does nothing when the page has no cloud markup", () => {
    assert.equal(autoStart(null), null, "no window at all");
    assert.equal(autoStart({}), null, "no document");
    assert.equal(autoStart({ document: {}, Game2048Game: {} }), null, "no cloud module");
    assert.equal(
        autoStart({ document: { getElementById: () => null }, Game2048Cloud: {}, Game2048Game: {} }),
        null,
        "a page without the account button is a page that opted out of the feature"
    );
});

test("autoStart gives up quietly when the browser has no storage", () => {
    const page = fakePage();
    const view = {
        document: page.document,
        Game2048Game: fakeGame(),
        Game2048Cloud: {
            createCloudClient() { throw new Error("no storage"); }
        }
    };

    assert.equal(autoStart(view), null, "the game must survive a browser that refuses storage");
    assert.equal(view.Game2048AccountUI, undefined);
});

test("autoStart wires the real factory when everything is present", () => {
    const page = fakePage();
    const cloud = fakeCloud();
    const view = {
        document: page.document,
        Game2048Game: fakeGame(),
        GAME2048_API_BASE_URL: "https://api.test",
        Game2048Cloud: { createCloudClient: options => (assert.equal(options.baseUrl, "https://api.test"), cloud) }
    };

    const ui = autoStart(view);

    assert.ok(ui);
    assert.equal(view.Game2048AccountUI, ui);
    assert.equal(page.elements.accountButtonLabel.textContent, "Sign in");
});

test("a sync failure right after signing in is reported, not swallowed", async () => {
    const cloud = fakeCloud({
        sync() {
            throw new Error("Could not reach the 2048 cloud.");
        }
    });
    const app = mount({ cloud });
    await app.ui.start();
    app.elements.accountButton.dispatch("click");

    await app.elements.authForm.dispatch("submit", { preventDefault() {} });
    await tick();

    assert.match(app.elements.cloudStatus.textContent, /Could not reach/);
    assert.deepEqual(app.game.applied, [], "a failed pull must not leave a half-applied board");
});

test("a profile refresh that fails after signing in is not an auth failure", async () => {
    const cloud = fakeCloud({
        sync: () => ({ resolution: "in_sync", save: null }),
        refreshUser() {
            throw new Error("offline");
        }
    });
    const app = mount({ cloud });
    await app.ui.start();
    app.elements.accountButton.dispatch("click");

    await app.elements.authForm.dispatch("submit", { preventDefault() {} });
    await tick();

    assert.equal(app.elements.authError.hidden, true);
    assert.match(app.elements.cloudStatus.textContent, /account is ready/);
});

test("a stored session adopts the account profile before the network answers", async () => {
    const remote = { board: new Array(16).fill(0).map((_, i) => (i === 0 ? 16 : 0)), score: 48, moves: 6, revision: 9 };
    const cloud = fakeCloud({
        restore: client => {
            client.setState({ signedIn: true, pending: false, user: { username: "ada", displayName: "Ada", statistics: {} } });
            return client.getState().user;
        },
        sync: () => ({ resolution: "downloaded", save: remote })
    });
    cloud.setState({ pending: true });
    const app = mount({
        cloud,
        game: fakeGame({ board: new Array(16).fill(2), score: 120, bestScore: 300, moves: 20 })
    });

    await app.ui.start();
    await tick();

    assert.deepEqual(app.game.sessions, [["begin", null]], "no confirmation is asked for a session already granted");
    assert.equal(app.game.profile, "account");
    const syncCall = app.cloud.calls.find(call => call[0] === "sync");
    assert.equal(syncCall[1], null, "with nothing cached there is nothing to offer the server");
    assert.deepEqual(app.game.applied, [remote]);
});

test("a stored session with a cached round reconciles it instead of pulling", async () => {
    const cached = { board: new Array(16).fill(0).map((_, i) => (i === 0 ? 32 : 0)), score: 96, moves: 11 };
    const cloud = fakeCloud({
        restore: client => {
            client.setState({ signedIn: true, pending: false, user: { username: "ada", displayName: "Ada", statistics: {} } });
            return client.getState().user;
        },
        sync: () => ({ resolution: "uploaded", save: { ...cached, revision: 3 } })
    });
    cloud.setState({ pending: true });
    const app = mount({
        cloud,
        game: fakeGame({ board: new Array(16).fill(2), score: 120, moves: 20 }, { cachedAccountRound: cached })
    });

    await app.ui.start();
    await tick();

    const syncCall = app.cloud.calls.find(call => call[0] === "sync");
    assert.equal(syncCall[1], cached, "the account's own cached round is what gets reconciled");
    assert.equal(syncCall[2], "auto");
});

test("a stored session that cannot be restored hands the device back to the guest", async () => {
    const cloud = fakeCloud({ restore: () => null });
    cloud.setState({ pending: true });
    const app = mount({
        cloud,
        game: fakeGame({ board: new Array(16).fill(2), score: 120, moves: 20 })
    });

    await app.ui.start();
    await tick();

    assert.deepEqual(app.game.sessions, [["begin", null], ["end", null]]);
    assert.equal(app.game.profile, "guest");
    assert.equal(app.game.current.score, 120, "an expired token costs the player nothing");
});

/* -------------------------------------------------------------------- */
/* Passwords                                                             */
/* -------------------------------------------------------------------- */

test("the confirmation field belongs to sign-up and not to sign-in", async () => {
    const app = mount();
    await app.ui.start();

    app.elements.accountButton.dispatch("click");
    assert.equal(app.elements.authConfirmField.hidden, false);

    app.elements.authSwitch.dispatch("click", { preventDefault() {} });
    assert.equal(app.elements.authConfirmField.hidden, true, "signing in tells you immediately that you mistyped");

    app.elements.authSwitch.dispatch("click", { preventDefault() {} });
    assert.equal(app.elements.authConfirmField.hidden, false);
});

test("a mismatched confirmation never reaches the network", async () => {
    const app = mount();
    await app.ui.start();
    app.elements.cloudBannerCreate.dispatch("click");
    app.elements.authUsername.value = "ada";
    app.elements.authEmail.value = "ada@example.test";
    app.elements.authPassword.value = "Password1";
    app.elements.authConfirm.value = "Password2";

    await app.elements.authForm.dispatch("submit", { preventDefault() {} });

    assert.equal(app.cloud.calls.some(call => call[0] === "register"), false);
    assert.equal(app.elements.authError.hidden, false);
    assert.match(app.elements.authError.textContent, /do not match/);
    assert.equal(app.elements.authDialog.open, true, "the form stays up so it can be corrected");
});

test("a matching confirmation is not sent to the server", async () => {
    const app = mount();
    await app.ui.start();
    app.elements.cloudBannerCreate.dispatch("click");
    app.elements.authUsername.value = "ada";
    app.elements.authEmail.value = "ada@example.test";
    app.elements.authPassword.value = "Password1";
    app.elements.authConfirm.value = "Password1";

    await app.elements.authForm.dispatch("submit", { preventDefault() {} });

    const register = app.cloud.calls.find(call => call[0] === "register");
    assert.deepEqual(Object.keys(register[1]).sort(), ["email", "password", "username"]);
    assert.equal(app.elements.authConfirm.value, "", "the confirmation is cleared with the password");
});

test("each password field reveals and hides on its own", async () => {
    const app = mount();
    await app.ui.start();
    app.elements.accountButton.dispatch("click");

    const button = app.reveal.authPassword;
    assert.equal(app.elements.authPassword.type, "password");

    button.dispatch("click");
    assert.equal(app.elements.authPassword.type, "text");
    assert.equal(button.getAttribute("aria-pressed"), "true");
    assert.equal(button.getAttribute("aria-label"), "Hide password");
    assert.equal(app.elements.authConfirm.type, "password", "revealing one field reveals only that field");

    button.dispatch("click");
    assert.equal(app.elements.authPassword.type, "password");
    assert.equal(button.getAttribute("aria-pressed"), "false");
    assert.equal(button.getAttribute("aria-label"), "Show password");
});

test("closing a form hides every password again", async () => {
    const app = mount();
    await app.ui.start();
    app.elements.accountButton.dispatch("click");
    app.reveal.authPassword.dispatch("click");
    app.reveal.authConfirm.dispatch("click");

    app.elements.authDismiss.dispatch("click");

    assert.equal(app.elements.authPassword.type, "password");
    assert.equal(app.elements.authConfirm.type, "password");
    assert.equal(app.reveal.authPassword.getAttribute("aria-pressed"), "false");
    assert.equal(app.reveal.authConfirm.getAttribute("aria-pressed"), "false");
});

/* -------------------------------------------------------------------- */
/* Password reset                                                        */
/* -------------------------------------------------------------------- */

test("forgot password opens the reset form, carrying what was already typed", async () => {
    const app = mount();
    await app.ui.start();
    app.elements.accountButton.dispatch("click");
    app.elements.authSwitch.dispatch("click", { preventDefault() {} });
    app.elements.authIdentifier.value = "  ada  ";

    app.elements.authForgot.dispatch("click", { preventDefault() {} });

    assert.equal(app.elements.authDialog.open, false);
    assert.equal(app.elements.resetDialog.open, true);
    assert.equal(app.elements.resetUsername.value, "ada");
});

test("a reset needs the two new passwords to agree", async () => {
    const app = mount();
    await app.ui.start();
    app.elements.accountButton.dispatch("click");
    app.elements.authForgot.dispatch("click", { preventDefault() {} });
    app.elements.resetUsername.value = "ada";
    app.elements.resetEmail.value = "ada@example.test";
    app.elements.resetPassword.value = "Recovered1";
    app.elements.resetConfirm.value = "Recovered2";

    await app.elements.resetForm.dispatch("submit", { preventDefault() {} });

    assert.equal(app.cloud.calls.some(call => call[0] === "resetPassword"), false);
    assert.match(app.elements.resetError.textContent, /do not match/);
    assert.equal(app.elements.resetDialog.open, true);
});

test("a successful reset sends the player back to sign in", async () => {
    const app = mount();
    await app.ui.start();
    app.elements.accountButton.dispatch("click");
    app.elements.authForgot.dispatch("click", { preventDefault() {} });
    app.elements.resetUsername.value = " ada ";
    app.elements.resetEmail.value = " ada@example.test ";
    app.elements.resetPassword.value = "Recovered1";
    app.elements.resetConfirm.value = "Recovered1";

    await app.elements.resetForm.dispatch("submit", { preventDefault() {} });
    await tick();

    const call = app.cloud.calls.find(entry => entry[0] === "resetPassword");
    assert.deepEqual(call[1], { username: "ada", email: "ada@example.test", newPassword: "Recovered1" });
    assert.equal(app.elements.resetDialog.open, false);
    assert.equal(app.elements.authDialog.open, true);
    assert.equal(app.elements.authTitle.textContent, "Welcome back");
    assert.match(app.elements.cloudStatus.textContent, /Sign in with your new password/);
    assert.equal(app.elements.resetPassword.value, "", "the new password does not linger in the form");
});

test("a rejected reset explains itself and keeps the form open", async () => {
    const cloud = fakeCloud({
        resetPassword() {
            throw new Error("That username and email do not match an account.");
        }
    });
    const app = mount({ cloud });
    await app.ui.start();
    app.elements.accountButton.dispatch("click");
    app.elements.authForgot.dispatch("click", { preventDefault() {} });
    app.elements.resetUsername.value = "ada";
    app.elements.resetEmail.value = "wrong@example.test";
    app.elements.resetPassword.value = "Recovered1";
    app.elements.resetConfirm.value = "Recovered1";

    await app.elements.resetForm.dispatch("submit", { preventDefault() {} });
    await tick();

    assert.equal(app.elements.resetDialog.open, true);
    assert.match(app.elements.resetError.textContent, /do not match an account/);
    assert.equal(app.elements.resetSubmit.disabled, false, "the button comes back so it can be retried");
});

test("resetting while signed in hands the device back to the guest round", async () => {
    const app = mount({ game: fakeGame({ board: new Array(16).fill(2), score: 80, moves: 12 }) });
    await app.ui.start();
    app.game.beginAccountSession({ fresh: true });
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });

    app.elements.accountButton.dispatch("click");
    app.elements.authForgot.dispatch("click", { preventDefault() {} });
    app.elements.resetUsername.value = "ada";
    app.elements.resetEmail.value = "ada@example.test";
    app.elements.resetPassword.value = "Recovered1";
    app.elements.resetConfirm.value = "Recovered1";
    await app.elements.resetForm.dispatch("submit", { preventDefault() {} });
    await tick();

    // A reset revokes every session, this one included.
    assert.equal(app.game.profile, "guest");
    assert.equal(app.game.current.score, 80);
});

test("dismissing the reset form clears it", async () => {
    const app = mount();
    await app.ui.start();
    app.elements.accountButton.dispatch("click");
    app.elements.authForgot.dispatch("click", { preventDefault() {} });
    app.elements.resetPassword.value = "Recovered1";
    app.reveal.resetPassword.dispatch("click");

    app.elements.resetDismiss.dispatch("click");

    assert.equal(app.elements.resetDialog.open, false);
    assert.equal(app.elements.resetPassword.value, "");
    assert.equal(app.elements.resetPassword.type, "password");

    // A backdrop click is the same answer.
    app.elements.authForgot.dispatch("click", { preventDefault() {} });
    app.elements.resetDialog.dispatch("click", { target: app.elements.resetDialog });
    assert.equal(app.elements.resetDialog.open, false);

    // And "Back to sign in" returns to the form it came from.
    app.elements.accountButton.dispatch("click");
    app.elements.authForgot.dispatch("click", { preventDefault() {} });
    app.elements.resetCancel.dispatch("click");
    assert.equal(app.elements.resetDialog.open, false);
    assert.equal(app.elements.authDialog.open, true);
});

test("a reset is ignored while another request is in flight", async () => {
    let resolve;
    const cloud = fakeCloud({ resetPassword: () => new Promise(next => { resolve = next; }) });
    const app = mount({ cloud });
    await app.ui.start();
    app.elements.accountButton.dispatch("click");
    app.elements.authForgot.dispatch("click", { preventDefault() {} });
    app.elements.resetPassword.value = "Recovered1";
    app.elements.resetConfirm.value = "Recovered1";

    const first = app.elements.resetForm.dispatch("submit", { preventDefault() {} });
    assert.equal(app.elements.resetSubmit.textContent, "Resetting…");
    assert.equal(app.elements.resetUsername.disabled, true);
    await app.elements.resetForm.dispatch("submit", { preventDefault() {} });
    assert.equal(app.cloud.calls.filter(call => call[0] === "resetPassword").length, 1);

    resolve({ reset: true });
    await first;
    await tick();
    assert.equal(app.elements.resetSubmit.textContent, "Reset password");
    assert.equal(app.elements.resetUsername.disabled, false);
});
