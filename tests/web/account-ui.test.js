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
    "authSubmit", "authSwitch", "authCancel", "authError",
    "accountDialog", "accountName", "accountEmail", "accountSummary", "accountSync",
    "accountSyncNow", "accountSignOut", "accountClose",
    "leaderboardDialog", "leaderboardPeriods", "leaderboardList", "leaderboardNote", "leaderboardClose"
];

function fakePage() {
    const elements = Object.fromEntries(IDS.map(id => [id, new FakeElement()]));
    elements.authError.hidden = true;
    elements.cloudBanner.hidden = true;

    for (const period of ["daily", "weekly", "all"]) {
        const button = new FakeElement("button");
        button.className = "period-button";
        button.dataset.period = period;
        elements.leaderboardPeriods.appendChild(button);
    }

    return {
        elements,
        document: {
            getElementById: id => elements[id] ?? null,
            createElement: tag => new FakeElement(tag)
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
        async submitScore(round) {
            calls.push(["submitScore", round]);
            if (overrides.submitScore) return overrides.submitScore(cloud, round);
            return { score: {} };
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
function fakeGame(save = { board: new Array(16).fill(0), score: 0, moves: 0, elapsedSeconds: 0 }) {
    const listeners = new Set();
    return {
        applied: [],
        current: save,
        getSave() { return this.current; },
        applySave(next) {
            this.applied.push(next);
            this.current = next;
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

/** A controllable clock, so a debounce is observable without waiting. */
function fakeTimers() {
    const pending = new Map();
    let nextId = 1;
    return {
        setTimeout(run) {
            const id = nextId++;
            pending.set(id, run);
            return id;
        },
        clearTimeout(id) { pending.delete(id); },
        pendingCount: () => pending.size,
        flush() {
            const runs = [...pending.values()];
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
        syncDelay: 10
    });
    return { ...page, cloud, game, timers, ui };
}

/* ---------------------------------------------------------------------- */

test("a signed-out player is invited, not blocked", async () => {
    const app = mount();
    await app.ui.start();

    assert.equal(app.elements.cloudBanner.hidden, false, "the invitation is visible");
    assert.equal(app.elements.accountButtonLabel.textContent, "Sign in");
    assert.match(app.elements.cloudStatus.textContent, /saved locally/);
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
});

test("cancelling closes the dialog and changes nothing", async () => {
    const app = mount();
    await app.ui.start();

    app.elements.accountButton.dispatch("click");
    app.elements.authCancel.dispatch("click");

    assert.equal(app.elements.authDialog.open, false);
    assert.equal(app.cloud.isSignedIn(), false);
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
    assert.match(app.elements.cloudStatus.textContent, /round stays on this device/);
});

test("sync now and done are wired", async () => {
    const app = mount();
    app.cloud.setState({ signedIn: true, user: { username: "ada", statistics: {} } });
    app.elements.accountButton.dispatch("click");

    await app.elements.accountSyncNow.dispatch("click");
    assert.ok(app.cloud.calls.some(call => call[0] === "sync"));

    app.elements.accountClose.dispatch("click");
    assert.equal(app.elements.accountDialog.open, false);
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

    assert.deepEqual(app.cloud.calls.map(call => call[0]), ["restore", "sync"]);
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
