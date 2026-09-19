"use strict";

// The cloud client, driven entirely through its injected `fetch` and storage.
//
// The interesting cases are the failure ones — a dropped connection, an
// expired token, a quota-full storage — and they are all reachable here
// precisely because nothing in `cloud.js` reaches for a global.

const test = require("node:test");
const assert = require("node:assert/strict");
const { createCloudClient, CloudError, TOKEN_KEY, PROMPT_KEY } = require("../../Web-Version/cloud.js");
const { FakeStorage } = require("./helpers/fake-dom.js");

const BASE = "https://api.test";

/** A fetch stand-in that replays queued responses and records every call. */
function fakeFetch(queue) {
    const calls = [];
    const responses = [...queue];
    const doFetch = async (url, init = {}) => {
        calls.push({ url, method: init.method ?? "GET", headers: init.headers ?? {}, body: init.body ? JSON.parse(init.body) : undefined });
        const next = responses.shift();
        if (!next) throw new Error(`No queued response for ${init.method ?? "GET"} ${url}`);
        if (next.throws) throw new Error(next.throws);
        return {
            ok: next.status >= 200 && next.status < 300,
            status: next.status,
            text: async () => (next.body === undefined ? "" : typeof next.body === "string" ? next.body : JSON.stringify(next.body))
        };
    };
    doFetch.calls = calls;
    doFetch.remaining = () => responses.length;
    return doFetch;
}

const SESSION = {
    accessToken: "access-1",
    refreshToken: "refresh-1",
    user: { id: "u1", username: "ada", displayName: "Ada", email: "ada@example.test", statistics: { bestScore: 100 } }
};

function client(queue, { storage = new FakeStorage(), ...rest } = {}) {
    const doFetch = fakeFetch(queue);
    return {
        cloud: createCloudClient({ baseUrl: BASE, fetch: doFetch, storage, now: () => 1_700_000_000_000, random: () => 0.5, ...rest }),
        fetch: doFetch,
        storage
    };
}

test("a fresh client is signed out and reports that the network is available", () => {
    const { cloud } = client([]);
    const state = cloud.getState();

    assert.equal(state.signedIn, false);
    assert.equal(state.available, true);
    assert.equal(state.user, null);
    assert.equal(cloud.isSignedIn(), false);
});

test("a client with no fetch at all still constructs and reports unavailable", async () => {
    const cloud = createCloudClient({ baseUrl: BASE, fetch: null, storage: new FakeStorage() });
    assert.equal(cloud.getState().available, false);
    await assert.rejects(() => cloud.login({ identifier: "a", password: "b" }), /cannot reach the network/);
});

test("a browser with no storage is refused rather than half-initialised", () => {
    assert.throws(() => createCloudClient({ baseUrl: BASE, fetch: async () => {}, storage: null }), CloudError);
});

test("registering stores the tokens and adopts the session", async () => {
    const { cloud, fetch: doFetch, storage } = client([{ status: 201, body: SESSION }]);

    const user = await cloud.register({ username: "ada", email: "ada@example.test", password: "Password1" });

    assert.equal(user.username, "ada");
    assert.equal(cloud.isSignedIn(), true);
    assert.equal(JSON.parse(storage.getItem(TOKEN_KEY)).accessToken, "access-1");
    assert.equal(doFetch.calls[0].url, `${BASE}/api/v1/auth/register`);
    assert.equal(doFetch.calls[0].body.client, "web", "every request identifies its client");
});

test("signing in sends the identifier the player typed", async () => {
    const { cloud, fetch: doFetch } = client([{ status: 200, body: SESSION }]);
    await cloud.login({ identifier: "ada@example.test", password: "Password1" });

    assert.equal(doFetch.calls[0].body.identifier, "ada@example.test");
    assert.equal(cloud.getState().user.username, "ada");
});

test("a rejected sign-in surfaces the server's message and code", async () => {
    const { cloud } = client([{ status: 401, body: { error: { code: "invalid_credentials", message: "That email or password is not correct." } } }]);

    await assert.rejects(
        () => cloud.login({ identifier: "ada", password: "wrong" }),
        error => {
            assert.equal(error.code, "invalid_credentials");
            assert.equal(error.status, 401);
            assert.match(error.message, /not correct/);
            return true;
        }
    );
    assert.equal(cloud.isSignedIn(), false);
});

test("an error response with no parsable body still produces a usable error", async () => {
    const { cloud } = client([{ status: 502, body: "<html>bad gateway</html>" }]);

    await assert.rejects(
        () => cloud.login({ identifier: "ada", password: "x" }),
        error => {
            assert.equal(error.code, "http_error");
            assert.match(error.message, /status 502/);
            return true;
        }
    );
});

test("a dropped connection is reported as a network error, not a crash", async () => {
    const { cloud } = client([{ throws: "ECONNREFUSED" }]);

    await assert.rejects(
        () => cloud.login({ identifier: "ada", password: "x" }),
        error => {
            assert.equal(error.code, "network");
            assert.match(error.message, /still saved on this device/, "the message must reassure, not alarm");
            return true;
        }
    );
});

test("subscribers are notified immediately and on every session change", async () => {
    const { cloud } = client([{ status: 201, body: SESSION }]);
    const seen = [];
    const unsubscribe = cloud.subscribe(state => seen.push(state.signedIn));

    assert.deepEqual(seen, [false]);
    await cloud.register({ username: "ada", email: "a@b.test", password: "Password1" });
    assert.deepEqual(seen, [false, true]);

    unsubscribe();
    await cloud.logout();
    assert.deepEqual(seen, [false, true], "an unsubscribed listener hears nothing further");
});

test("restoring with no stored token resolves to null without a request", async () => {
    const { cloud, fetch: doFetch } = client([]);
    assert.equal(await cloud.restore(), null);
    assert.equal(doFetch.calls.length, 0, "there is nothing to ask about");
});

test("restoring re-establishes a session from stored tokens", async () => {
    const storage = new FakeStorage({ [TOKEN_KEY]: JSON.stringify({ accessToken: "access-1", refreshToken: "refresh-1" }) });
    const { cloud } = client([{ status: 200, body: { user: SESSION.user } }], { storage });

    const user = await cloud.restore();
    assert.equal(user.username, "ada");
    assert.equal(cloud.isSignedIn(), true);
});

test("a network failure while restoring keeps the player signed in", async () => {
    // Someone on a train has not been signed out; they are simply offline.
    const storage = new FakeStorage({ [TOKEN_KEY]: JSON.stringify({ accessToken: "access-1", refreshToken: "refresh-1" }) });
    const { cloud } = client([{ throws: "offline" }], { storage });

    assert.equal(await cloud.restore(), null);
    assert.ok(storage.getItem(TOKEN_KEY), "the tokens must survive a failed reachability check");
    assert.match(cloud.getState().lastError, /Could not reach/);
});

test("a rejected token while restoring does sign the player out", async () => {
    const storage = new FakeStorage({ [TOKEN_KEY]: JSON.stringify({ accessToken: "stale", refreshToken: "also-stale" }) });
    const { cloud } = client(
        [
            { status: 401, body: { error: { code: "unauthorized", message: "expired" } } },
            { status: 401, body: { error: { code: "unauthorized", message: "gone" } } }
        ],
        { storage }
    );

    assert.equal(await cloud.restore(), null);
    assert.equal(storage.getItem(TOKEN_KEY), null, "an unusable token is discarded");
    assert.equal(cloud.isSignedIn(), false);
});

test("a corrupt token entry is discarded instead of crashing the page", () => {
    const storage = new FakeStorage({ [TOKEN_KEY]: "{not json" });
    const { cloud } = client([]);
    const salvaged = createCloudClient({ baseUrl: BASE, fetch: async () => {}, storage });

    assert.equal(storage.getItem(TOKEN_KEY), null);
    assert.equal(salvaged.isSignedIn(), false);
    assert.equal(cloud.isSignedIn(), false);
});

test("an expired access token is refreshed once and the request is retried", async () => {
    const storage = new FakeStorage({ [TOKEN_KEY]: JSON.stringify({ accessToken: "old", refreshToken: "refresh-1" }) });
    const { cloud, fetch: doFetch } = client(
        [
            { status: 401, body: { error: { code: "unauthorized", message: "expired" } } },
            { status: 200, body: { ...SESSION, accessToken: "access-2", refreshToken: "refresh-2" } },
            { status: 200, body: { user: SESSION.user } }
        ],
        { storage }
    );

    const user = await cloud.restore();

    assert.equal(user.username, "ada");
    assert.equal(doFetch.calls[1].url, `${BASE}/api/v1/auth/refresh`);
    assert.equal(doFetch.calls[2].headers.authorization, "Bearer access-2", "the retry must carry the new token");
    assert.equal(JSON.parse(storage.getItem(TOKEN_KEY)).refreshToken, "refresh-2");
});

test("two requests racing an expiry share one refresh", async () => {
    // Refreshing twice would rotate the token twice, and the server treats the
    // second rotation as a replay — which revokes the session. A signed-in
    // player must not be signed out by their own parallel requests.
    const storage = new FakeStorage({ [TOKEN_KEY]: JSON.stringify({ accessToken: "old", refreshToken: "refresh-1" }) });
    const { cloud, fetch: doFetch } = client(
        [
            { status: 401, body: { error: { code: "unauthorized", message: "expired" } } },
            { status: 401, body: { error: { code: "unauthorized", message: "expired" } } },
            { status: 200, body: { ...SESSION, accessToken: "access-2", refreshToken: "refresh-2" } },
            { status: 200, body: { items: [] } },
            { status: 200, body: { items: [] } }
        ],
        { storage }
    );

    await Promise.all([cloud.stats(), cloud.achievements()]);

    const refreshCalls = doFetch.calls.filter(call => call.url.endsWith("/auth/refresh"));
    assert.equal(refreshCalls.length, 1, `expected exactly one refresh, saw ${refreshCalls.length}`);
});

test("a failed refresh signs the player out rather than looping", async () => {
    const storage = new FakeStorage({ [TOKEN_KEY]: JSON.stringify({ accessToken: "old", refreshToken: "dead" }) });
    const { cloud } = client(
        [
            { status: 401, body: { error: { code: "unauthorized", message: "expired" } } },
            { status: 401, body: { error: { code: "unauthorized", message: "that session is gone" } } }
        ],
        { storage }
    );

    await assert.rejects(() => cloud.stats());
    assert.equal(cloud.isSignedIn(), false);
    assert.equal(storage.getItem(TOKEN_KEY), null);
});

test("an authenticated call without a session fails before touching the network", async () => {
    const { cloud, fetch: doFetch } = client([]);
    await assert.rejects(() => cloud.stats(), /Sign in/);
    assert.equal(doFetch.calls.length, 0);
});

test("syncing sends the local save and records the resolution", async () => {
    const { cloud, fetch: doFetch } = client([
        { status: 201, body: SESSION },
        { status: 200, body: { resolution: "uploaded", save: { board: [], score: 10 }, conflictSlot: null } }
    ]);

    await cloud.register({ username: "ada", email: "a@b.test", password: "Password1" });
    const result = await cloud.sync({ board: new Array(16).fill(0), score: 10, moves: 2 });

    assert.equal(result.resolution, "uploaded");
    assert.equal(cloud.getState().lastResolution, "uploaded");
    assert.equal(cloud.getState().lastSync, "2023-11-14T22:13:20.000Z");

    const body = doFetch.calls[1].body;
    assert.equal(body.slot, "current");
    assert.equal(body.strategy, "auto");
    assert.equal(body.save.client, "web");
    assert.ok(body.save.deviceId.startsWith("web-"), "a save carries a local device identifier so a conflict can name it");
});

test("syncing with no local save sends null rather than an empty board", async () => {
    const { cloud, fetch: doFetch } = client([
        { status: 201, body: SESSION },
        { status: 200, body: { resolution: "downloaded", save: null } }
    ]);

    await cloud.register({ username: "ada", email: "a@b.test", password: "Password1" });
    await cloud.sync(null);

    assert.equal(doFetch.calls[1].body.save, null, "an empty board is a round; no save at all is not");
});

test("a chosen strategy is passed through", async () => {
    const { cloud, fetch: doFetch } = client([
        { status: 201, body: SESSION },
        { status: 200, body: { resolution: "uploaded", save: null } }
    ]);

    await cloud.register({ username: "ada", email: "a@b.test", password: "Password1" });
    await cloud.sync({ board: new Array(16).fill(0), score: 0 }, "prefer-local");

    assert.equal(doFetch.calls[1].body.strategy, "prefer-local");
});

test("the leaderboard is readable signed out and authenticated when signed in", async () => {
    const signedOut = client([{ status: 200, body: { entries: [] } }]);
    await signedOut.cloud.leaderboard({ period: "weekly", limit: 5 });
    assert.equal(signedOut.fetch.calls[0].headers.authorization, undefined, "a signed-out reader still sees the board");
    assert.match(signedOut.fetch.calls[0].url, /period=weekly&limit=5&offset=0/);

    const signedIn = client([
        { status: 201, body: SESSION },
        { status: 200, body: { entries: [] } }
    ]);
    await signedIn.cloud.register({ username: "ada", email: "a@b.test", password: "Password1" });
    await signedIn.cloud.leaderboard();
    assert.equal(signedIn.fetch.calls[1].headers.authorization, "Bearer access-1");
});

test("the daily challenge is readable both ways too", async () => {
    const signedOut = client([{ status: 200, body: { challenge: { date: "2026-09-18" } } }]);
    await signedOut.cloud.dailyChallenge();
    assert.equal(signedOut.fetch.calls[0].headers.authorization, undefined);
});

test("every authenticated read reaches its documented path", async () => {
    const { cloud, fetch: doFetch } = client([
        { status: 201, body: SESSION },
        { status: 200, body: {} },
        { status: 200, body: {} },
        { status: 200, body: {} },
        { status: 200, body: {} },
        { status: 201, body: {} }
    ]);

    await cloud.register({ username: "ada", email: "a@b.test", password: "Password1" });
    await cloud.myRank("monthly");
    await cloud.stats();
    await cloud.achievements();
    await cloud.preferences({ theme: "dark" });
    await cloud.submitScore({ board: new Array(16).fill(0), score: 10 });

    assert.deepEqual(doFetch.calls.slice(1).map(call => `${call.method} ${call.url.replace(BASE, "")}`), [
        "GET /api/v1/leaderboard/me?period=monthly",
        "GET /api/v1/stats/me",
        "GET /api/v1/achievements/me",
        "PUT /api/v1/users/me/preferences",
        "POST /api/v1/scores"
    ]);
});

test("signing out clears the session even when the server call fails", async () => {
    const { cloud, storage } = client([
        { status: 201, body: SESSION },
        { throws: "offline" }
    ]);

    await cloud.register({ username: "ada", email: "a@b.test", password: "Password1" });
    await cloud.logout();

    assert.equal(cloud.isSignedIn(), false);
    assert.equal(storage.getItem(TOKEN_KEY), null, "the player asked to be signed out; a failed revoke does not change that");
});

test("signing out with nothing stored makes no request", async () => {
    const { cloud, fetch: doFetch } = client([]);
    await cloud.logout();
    assert.equal(doFetch.calls.length, 0);
});

test("deleting the account clears the local session", async () => {
    const { cloud, storage } = client([
        { status: 201, body: SESSION },
        { status: 200, body: { deleted: true } }
    ]);

    await cloud.register({ username: "ada", email: "a@b.test", password: "Password1" });
    await cloud.deleteAccount("Password1");

    assert.equal(cloud.isSignedIn(), false);
    assert.equal(storage.getItem(TOKEN_KEY), null);
});

test("the sign-up prompt can be dismissed and stays dismissed", () => {
    const storage = new FakeStorage();
    const { cloud } = client([], { storage });

    assert.equal(cloud.promptDismissed(), false);
    cloud.dismissPrompt();
    assert.equal(cloud.promptDismissed(), true);
    assert.equal(storage.getItem(PROMPT_KEY), "dismissed");
});

test("a storage that refuses to write does not break anything", () => {
    // Private browsing and a full quota both throw on setItem. Losing a token
    // means signing in again; it must never mean losing the game.
    const readOnly = {
        getItem: () => null,
        setItem() { throw new Error("QuotaExceededError"); },
        removeItem: () => {}
    };
    const cloud = createCloudClient({ baseUrl: BASE, fetch: async () => {}, storage: readOnly, random: () => 0.25 });

    assert.doesNotThrow(() => cloud.dismissPrompt());
    assert.ok(cloud.getState().deviceId.startsWith("web-"));
});

test("signing in survives a storage that cannot hold the token", async () => {
    const readOnly = {
        getItem: () => null,
        setItem() { throw new Error("QuotaExceededError"); },
        removeItem: () => {}
    };
    const doFetch = fakeFetch([{ status: 201, body: SESSION }]);
    const cloud = createCloudClient({ baseUrl: BASE, fetch: doFetch, storage: readOnly, random: () => 0.1 });

    await cloud.register({ username: "ada", email: "a@b.test", password: "Password1" });

    // The session is live for this tab even though nothing could be persisted;
    // the player simply signs in again next visit.
    assert.equal(cloud.isSignedIn(), true);
});

test("a storage that throws on read still yields a device identifier", () => {
    const hostile = {
        getItem() { throw new Error("blocked"); },
        setItem() { throw new Error("blocked"); },
        removeItem: () => {}
    };
    const cloud = createCloudClient({ baseUrl: BASE, fetch: async () => {}, storage: hostile, random: () => 0.75 });
    assert.ok(cloud.getState().deviceId.startsWith("web-"));
});

test("the device identifier is stable across calls", () => {
    const storage = new FakeStorage();
    const { cloud } = client([], { storage });
    assert.equal(cloud.getState().deviceId, cloud.getState().deviceId);
});

test("a trailing slash on the base URL does not produce a double slash", async () => {
    const doFetch = fakeFetch([{ status: 200, body: {} }]);
    const cloud = createCloudClient({ baseUrl: "https://api.test///", fetch: doFetch, storage: new FakeStorage() });

    await cloud.leaderboard();
    assert.equal(doFetch.calls[0].url.startsWith("https://api.test/api/v1/"), true);
});

test("a successful response with an empty body resolves to null", async () => {
    const { cloud } = client([{ status: 200, body: undefined }]);
    assert.equal(await cloud.leaderboard(), null);
});

test("the defaults point at the deployed API and the platform clock", async () => {
    const doFetch = fakeFetch([{ status: 200, body: {} }]);
    const cloud = createCloudClient({ fetch: doFetch, storage: new FakeStorage() });

    await cloud.leaderboard();

    assert.equal(doFetch.calls[0].url, "https://game-2048-cloud-api.vercel.app/api/v1/leaderboard?period=all&limit=10&offset=0");
    assert.match(cloud.getState().deviceId, /^web-[a-z0-9]+$/, "the default generator still produces an identifier");
});

test("refreshing without a stored refresh token rejects rather than calling out", async () => {
    const storage = new FakeStorage({ [TOKEN_KEY]: JSON.stringify({ accessToken: "orphan" }) });
    const { cloud, fetch: doFetch } = client([{ status: 401, body: { error: { code: "unauthorized", message: "expired" } } }], { storage });

    // An access token with no refresh alongside it is a half-written entry.
    // It must fail cleanly, not attempt a refresh with `undefined`.
    await assert.rejects(() => cloud.stats(), /signed out/i);
    assert.equal(doFetch.calls.length, 1);
});

test("the daily challenge is authenticated once the player signs in", async () => {
    const { cloud, fetch: doFetch } = client([
        { status: 201, body: SESSION },
        { status: 200, body: { challenge: { date: "2026-09-18" }, attempted: false } }
    ]);

    await cloud.register({ username: "ada", email: "a@b.test", password: "Password1" });
    await cloud.dailyChallenge();

    assert.equal(doFetch.calls[1].headers.authorization, "Bearer access-1");
});
