/**
 * Integration tests against a real MongoDB.
 *
 * These are skipped unless `MONGODB_TEST_URI` is set, so `npm test` stays a
 * fast, hermetic unit run and nobody's first clone fails because they have no
 * database. The guard on the database name is not decoration: pointing this
 * file at a production connection string would drop real player data.
 */
import assert from "node:assert/strict";
import test, { after, before } from "node:test";
import request from "supertest";

const uri = process.env.MONGODB_TEST_URI;
const dbName = process.env.MONGODB_TEST_DB ?? "game2048_test";

if (uri && !dbName.endsWith("_test")) {
    throw new Error(`Refusing to run integration tests against "${dbName}"; the database name must end in _test.`);
}

// The config module reads the environment once at import, so these have to be
// in place before anything else is imported.
process.env.NODE_ENV = "test";
process.env.MONGODB_URI = uri ?? "";
process.env.MONGODB_DB = dbName;
process.env.RATE_LIMIT_ENABLED = "false";
process.env.LOG_LEVEL = "silent";
process.env.JWT_ACCESS_SECRET ??= "integration-access-secret-value";
process.env.JWT_REFRESH_SECRET ??= "integration-refresh-secret-value";

const suite = uri ? test : test.skip;

const { createApp } = await import("../../src/app.js");
const { connectToDatabase, disconnectFromDatabase } = await import("../../src/config/database.js");
const models = await import("../../src/models/index.js");

const app = createApp();
const agent = () => request(app);

const PLAUSIBLE_BOARD = [512, 256, 128, 64, 32, 16, 8, 4, 2, 0, 0, 0, 0, 0, 0, 0];
const PLAUSIBLE_SCORE = 5600;

let unique = 0;
function newAccount() {
    unique += 1;
    const tag = `${Date.now().toString(36)}${unique}`;
    return { username: `it${tag}`, email: `it-${tag}@example.test`, password: "Integration123", client: "cli" };
}

async function register() {
    const account = newAccount();
    const response = await agent().post("/api/v1/auth/register").send(account).expect(201);
    return { account, tokens: response.body, auth: `Bearer ${response.body.accessToken}` };
}

before(async () => {
    if (!uri) return;
    await connectToDatabase();
    // A previous interrupted run can leave rows behind; start from a known
    // state rather than inheriting one.
    await Promise.all(Object.values(models).map(model => model.deleteMany({})));
});

after(async () => {
    if (!uri) return;
    await Promise.all(Object.values(models).map(model => model.deleteMany({})));
    await disconnectFromDatabase();
});

suite("the service root sends visitors to Swagger UI", async () => {
    const response = await agent().get("/").redirects(0).expect(302);
    assert.equal(response.headers.location, "/docs");
});

suite("Swagger UI is reachable at /docs", async () => {
    const response = await agent().get("/docs").expect(200);
    assert.match(response.text, /swagger-ui/i);
});

suite("liveness does not require the database and readiness does", async () => {
    await agent().get("/api/v1/health").expect(200);
    const ready = await agent().get("/api/v1/ready").expect(200);
    assert.equal(ready.body.database.state, "connected");
});

suite("an unknown route returns the standard error envelope", async () => {
    const response = await agent().get("/api/v1/not-a-route").expect(404);
    assert.equal(response.body.error.code, "route_not_found");
    assert.ok(response.body.requestId, "every error carries the request id");
});

suite("registration issues a usable token pair", async () => {
    const { tokens, auth } = await register();
    assert.equal(tokens.tokenType, "Bearer");
    assert.ok(tokens.accessToken && tokens.refreshToken);
    assert.equal(tokens.user.email.includes("@"), true);

    const me = await agent().get("/api/v1/auth/me").set("authorization", auth).expect(200);
    assert.equal(me.body.user.username, tokens.user.username);
});

suite("a password hash is never returned", async () => {
    const { tokens, auth } = await register();
    const me = await agent().get("/api/v1/auth/me").set("authorization", auth).expect(200);
    assert.equal("passwordHash" in me.body.user, false);
    assert.equal(JSON.stringify(tokens).includes("passwordHash"), false);
});

suite("a public profile withholds the email address", async () => {
    const { tokens } = await register();
    const profile = await agent().get(`/api/v1/users/${tokens.user.username}`).expect(200);
    assert.equal("email" in profile.body.user, false, "a public profile must not carry an email address");
});

suite("an unknown account and a wrong password are indistinguishable", async () => {
    const { account } = await register();
    const wrongPassword = await agent().post("/api/v1/auth/login").send({ identifier: account.username, password: "WrongPassword1" }).expect(401);
    const unknownUser = await agent().post("/api/v1/auth/login").send({ identifier: "nobody-at-all", password: "WrongPassword1" }).expect(401);
    assert.equal(wrongPassword.body.error.code, unknownUser.body.error.code);
    assert.equal(wrongPassword.body.error.message, unknownUser.body.error.message);
});

suite("sign in works with either a username or an email address", async () => {
    const { account } = await register();
    await agent().post("/api/v1/auth/login").send({ identifier: account.username, password: account.password }).expect(200);
    await agent().post("/api/v1/auth/login").send({ identifier: account.email, password: account.password }).expect(200);
    await agent().post("/api/v1/auth/login").send({ identifier: account.username.toUpperCase(), password: account.password }).expect(200);
});

suite("refreshing rotates the pair and replaying the old token kills the session", async () => {
    const { tokens } = await register();
    const refreshed = await agent().post("/api/v1/auth/refresh").send({ refreshToken: tokens.refreshToken }).expect(200);
    assert.notEqual(refreshed.body.refreshToken, tokens.refreshToken, "the refresh token must rotate");

    const replay = await agent().post("/api/v1/auth/refresh").send({ refreshToken: tokens.refreshToken }).expect(401);
    assert.match(replay.body.error.message, /already been rotated/);

    const afterRevocation = await agent().post("/api/v1/auth/refresh").send({ refreshToken: refreshed.body.refreshToken }).expect(401);
    assert.equal(afterRevocation.status, 401, "detecting reuse revokes the session, not just the token");
});

suite("a cloud save round-trips and reports the same board to both client shapes", async () => {
    const { auth } = await register();
    const upload = await agent()
        .post("/api/v1/saves/sync")
        .set("authorization", auth)
        .send({ save: { board: PLAUSIBLE_BOARD, score: 1000, moves: 100, client: "web" } })
        .expect(200);

    assert.equal(upload.body.resolution, "uploaded");
    assert.deepEqual(upload.body.save.board, PLAUSIBLE_BOARD);
    assert.deepEqual(upload.body.save.grid[0], [512, 256, 128, 64], "natives read rows; the same save must serve both");
});

suite("a divergent second device conflicts and nothing is lost", async () => {
    const { auth } = await register();
    await agent()
        .post("/api/v1/saves/sync")
        .set("authorization", auth)
        .send({ save: { board: PLAUSIBLE_BOARD, score: 4000, moves: 300, client: "web" } })
        .expect(200);

    const conflict = await agent()
        .post("/api/v1/saves/sync")
        .set("authorization", auth)
        .send({ save: { board: [2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], score: 4, moves: 1, client: "ios" } })
        .expect(200);

    assert.equal(conflict.body.resolution, "conflicted");
    assert.equal(conflict.body.winner, "remote", "the further round wins");
    assert.ok(conflict.body.conflictSlot);

    const slots = await agent().get("/api/v1/saves").set("authorization", auth).expect(200);
    const preserved = slots.body.items.find(save => save.slot === conflict.body.conflictSlot);
    assert.ok(preserved, "the losing round must remain recoverable");
    assert.equal(preserved.score, 4);
});

suite("a continuation carrying baseRevision uploads without conflicting", async () => {
    const { auth } = await register();
    const first = await agent()
        .post("/api/v1/saves/sync")
        .set("authorization", auth)
        .send({ save: { board: PLAUSIBLE_BOARD, score: 4000, moves: 300, client: "web" } })
        .expect(200);

    const second = await agent()
        .post("/api/v1/saves/sync")
        .set("authorization", auth)
        .send({ save: { board: PLAUSIBLE_BOARD, score: 4200, moves: 310, baseRevision: first.body.save.revision, client: "web" } })
        .expect(200);

    assert.equal(second.body.resolution, "uploaded");
    assert.equal(second.body.save.revision, first.body.save.revision + 1);
});

suite("a save with a malformed board is refused", async () => {
    const { auth } = await register();
    await agent()
        .post("/api/v1/saves/sync")
        .set("authorization", auth)
        .send({ save: { board: [1, 2, 3], score: 10 } })
        .expect(422);
});

suite("submitting a score is idempotent", async () => {
    const { auth } = await register();
    const payload = { board: PLAUSIBLE_BOARD, score: PLAUSIBLE_SCORE, moves: 480, durationSeconds: 600, client: "web" };

    const first = await agent().post("/api/v1/scores").set("authorization", auth).send(payload).expect(201);
    assert.equal(first.body.duplicate, false);
    assert.equal(first.body.score.verified, true);

    const second = await agent().post("/api/v1/scores").set("authorization", auth).send(payload).expect(200);
    assert.equal(second.body.duplicate, true);
    assert.equal(second.body.score.id, first.body.score.id, "a retry must return the original row");
});

suite("an impossible score is stored unverified and stays off the leaderboard", async () => {
    const { auth, tokens } = await register();
    const submission = await agent()
        .post("/api/v1/scores")
        .set("authorization", auth)
        .send({ board: [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], score: 9_000_000, client: "web" })
        .expect(201);

    assert.equal(submission.body.score.verified, false);

    const rank = await agent().get("/api/v1/leaderboard/me?period=all").set("authorization", auth).expect(200);
    assert.equal(rank.body.ranked, false, `${tokens.user.username} should not be ranked by an unverified round`);
});

suite("the leaderboard shows one row per player, not one per round", async () => {
    const { auth } = await register();
    for (const score of [3000, 5600, 4200]) {
        await agent()
            .post("/api/v1/scores")
            .set("authorization", auth)
            .send({ board: PLAUSIBLE_BOARD, score, moves: 400, client: "web" })
            .expect(201);
    }

    const board = await agent().get("/api/v1/leaderboard?period=all&limit=100").set("authorization", auth).expect(200);
    const mine = board.body.entries.filter(entry => entry.isViewer);
    assert.equal(mine.length, 1, "three rounds must collapse to one leaderboard row");
    assert.equal(mine[0].score, 5600, "the row shows the player's best, not their latest");
    assert.equal(mine[0].entries, 3, "the row still reports how many rounds it summarises");
});

suite("opting out hides a player's row without deleting their scores", async () => {
    const { auth } = await register();
    await agent().post("/api/v1/scores").set("authorization", auth).send({ board: PLAUSIBLE_BOARD, score: 5000, client: "web" }).expect(201);

    const before = await agent().get("/api/v1/leaderboard?period=all&limit=100").set("authorization", auth).expect(200);
    assert.ok(before.body.entries.some(entry => entry.isViewer));

    await agent().put("/api/v1/users/me/preferences").set("authorization", auth).send({ showOnLeaderboard: false }).expect(200);
    const hidden = await agent().get("/api/v1/leaderboard?period=all&limit=100").set("authorization", auth).expect(200);
    assert.equal(hidden.body.entries.some(entry => entry.isViewer), false);

    await agent().put("/api/v1/users/me/preferences").set("authorization", auth).send({ showOnLeaderboard: true }).expect(200);
    const restored = await agent().get("/api/v1/leaderboard?period=all&limit=100").set("authorization", auth).expect(200);
    assert.ok(restored.body.entries.some(entry => entry.isViewer), "turning the setting back on restores the same row");
});

suite("achievements unlock from a submitted round", async () => {
    const { auth } = await register();
    const submission = await agent()
        .post("/api/v1/scores")
        .set("authorization", auth)
        .send({ board: PLAUSIBLE_BOARD, score: PLAUSIBLE_SCORE, moves: 480, client: "web" })
        .expect(201);

    const keys = submission.body.unlockedAchievements.map(achievement => achievement.key);
    assert.ok(keys.includes("first_game"), `expected first_game, saw ${keys.join(", ") || "nothing"}`);

    const mine = await agent().get("/api/v1/achievements/me").set("authorization", auth).expect(200);
    assert.ok(mine.body.summary.unlocked > 0);
    assert.equal(mine.body.items.length, (await agent().get("/api/v1/achievements").expect(200)).body.items.length, "the catalog and the player view must list the same achievements");
});

suite("following scopes the friends leaderboard", async () => {
    const me = await register();
    const friend = await register();
    const stranger = await register();

    for (const player of [me, friend, stranger]) {
        await agent().post("/api/v1/scores").set("authorization", player.auth).send({ board: PLAUSIBLE_BOARD, score: 5000, client: "web" }).expect(201);
    }

    await agent().post(`/api/v1/social/follow/${friend.tokens.user.username}`).set("authorization", me.auth).expect(201);
    // Following twice is idempotent rather than a duplicate-key error.
    await agent().post(`/api/v1/social/follow/${friend.tokens.user.username}`).set("authorization", me.auth).expect(200);

    const board = await agent().get("/api/v1/leaderboard/friends?period=all&limit=100").set("authorization", me.auth).expect(200);
    const usernames = board.body.entries.map(entry => entry.username);
    assert.ok(usernames.includes(me.tokens.user.username), "the viewer is on their own friends board");
    assert.ok(usernames.includes(friend.tokens.user.username));
    assert.equal(usernames.includes(stranger.tokens.user.username), false, "a stranger must not appear");
});

suite("a player cannot follow themselves", async () => {
    const { auth, tokens } = await register();
    await agent().post(`/api/v1/social/follow/${tokens.user.username}`).set("authorization", auth).expect(400);
});

suite("the daily challenge is the same board for everyone and only today accepts a score", async () => {
    const first = await register();
    const second = await register();

    const a = await agent().get("/api/v1/challenges/daily").set("authorization", first.auth).expect(200);
    const b = await agent().get("/api/v1/challenges/daily").set("authorization", second.auth).expect(200);
    assert.deepEqual(a.body.challenge.board, b.body.challenge.board);

    await agent()
        .post("/api/v1/challenges/daily/submit")
        .set("authorization", first.auth)
        .send({ date: "2020-01-01", board: PLAUSIBLE_BOARD, score: 1000, client: "web" })
        .expect(400);

    const submitted = await agent()
        .post("/api/v1/challenges/daily/submit")
        .set("authorization", first.auth)
        .send({ board: PLAUSIBLE_BOARD, score: 1000, client: "web" })
        .expect(201);
    assert.equal(submitted.body.rank >= 1, true);
});

suite("deleting an account removes every row that referenced it", async () => {
    const { auth, account, tokens } = await register();
    await agent().post("/api/v1/scores").set("authorization", auth).send({ board: PLAUSIBLE_BOARD, score: 4000, client: "web" }).expect(201);
    await agent().post("/api/v1/saves/sync").set("authorization", auth).send({ save: { board: PLAUSIBLE_BOARD, score: 4000 } }).expect(200);

    await agent().delete("/api/v1/auth/me").set("authorization", auth).send({ password: account.password, confirm: "DELETE" }).expect(200);

    await agent().get(`/api/v1/users/${tokens.user.username}`).expect(404);
    const userId = tokens.user.id;
    for (const [name, model] of Object.entries(models)) {
        if (name === "User" || name === "Follow") continue;
        const remaining = await model.countDocuments({ user: userId });
        assert.equal(remaining, 0, `${name} still holds rows for the deleted account`);
    }

    // Follow edges are keyed by direction rather than by a `user` field, so
    // they need their own query. Checking `{ user: userId }` here would match
    // every document in the collection, because Mongoose strips the unknown
    // path and the filter becomes empty — a false pass dressed as a real one.
    assert.equal(await models.Follow.countDocuments({ $or: [{ follower: userId }, { following: userId }] }), 0);
});

suite("deleting an account requires the correct password", async () => {
    const { auth } = await register();
    await agent().delete("/api/v1/auth/me").set("authorization", auth).send({ password: "NotThePassword1", confirm: "DELETE" }).expect(401);
    await agent().delete("/api/v1/auth/me").set("authorization", auth).send({ password: "whatever", confirm: "yes" }).expect(422);
});
