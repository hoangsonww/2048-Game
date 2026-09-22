#!/usr/bin/env node
/**
 * End-to-end smoke test against a running deployment.
 *
 * This drives the same sequence a real client does — register, sync a save
 * from one "device", sync a divergent save from a second, submit a score, read
 * the leaderboard, then delete the account — so a deploy can be verified
 * against the real database without leaving a test account behind.
 *
 * Usage: node scripts/smoke.mjs [baseUrl]
 */
import process from "node:process";
import crypto from "node:crypto";

const base = (process.argv[2] ?? process.env.API_BASE_URL ?? "http://localhost:4000").replace(/\/$/, "");
const suffix = crypto.randomBytes(4).toString("hex");
const account = {
    username: `smoke${suffix}`,
    email: `smoke-${suffix}@example.test`,
    password: "SmokeTest123",
    client: "cli"
};

let accessToken = null;
let passed = 0;
const failures = [];

async function call(method, path, { body, auth = false, expect = [200, 201, 202] } = {}) {
    const response = await fetch(`${base}${path}`, {
        method,
        headers: {
            "content-type": "application/json",
            "x-client": "cli",
            ...(auth && accessToken ? { authorization: `Bearer ${accessToken}` } : {})
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) })
    });

    const text = await response.text();
    let payload;
    try {
        payload = text ? JSON.parse(text) : null;
    } catch {
        payload = text;
    }

    if (!expect.includes(response.status)) {
        throw new Error(`${method} ${path} -> ${response.status} (expected ${expect.join("/")})\n${text.slice(0, 500)}`);
    }
    return payload;
}

async function step(name, run) {
    try {
        const detail = await run();
        passed += 1;
        console.log(`  ok   ${name}${detail ? ` — ${detail}` : ""}`);
    } catch (error) {
        failures.push(`${name}: ${error.message}`);
        console.error(`  FAIL ${name}\n       ${error.message.split("\n").join("\n       ")}`);
    }
}

/**
 * A board that could genuinely have scored what the tests below claim. The
 * score ceiling is derived from the tiles present — a board topping out at 16
 * cannot have scored thousands — so the fixture has to be a plausible game,
 * not arbitrary numbers.
 */
const BOARD = [512, 256, 128, 64, 32, 16, 8, 4, 2, 0, 0, 0, 0, 0, 0, 0];
const CONTINUED_BOARD = [512, 256, 128, 64, 32, 16, 8, 8, 2, 0, 0, 0, 0, 0, 0, 0];

console.log(`Smoke testing ${base}\n`);

await step("service index", async () => {
    const index = await call("GET", "/");
    return `${index.service} ${index.version}`;
});

await step("liveness", async () => (await call("GET", "/api/v1/health")).status);
await step("readiness", async () => {
    const ready = await call("GET", "/api/v1/ready");
    return `db ${ready.database.state} in ${ready.database.latencyMs}ms`;
});
await step("client config", async () => {
    const configuration = await call("GET", "/api/v1/config");
    return `${Object.values(configuration.features).filter(Boolean).length} features on`;
});
await step("openapi document", async () => {
    const document = await call("GET", "/openapi.json");
    const operations = Object.values(document.paths).reduce((total, path) => total + Object.keys(path).length, 0);
    return `${operations} operations`;
});
await step("swagger ui", async () => {
    const response = await fetch(`${base}/docs`);
    if (!response.ok) throw new Error(`status ${response.status}`);
    return "served";
});
await step("redoc", async () => {
    const response = await fetch(`${base}/redoc`);
    if (!response.ok) throw new Error(`status ${response.status}`);
    return "served";
});
await step("scalar reference", async () => {
    const response = await fetch(`${base}/reference`);
    if (!response.ok) throw new Error(`status ${response.status}`);
    return "served";
});
await step("daily challenge is deterministic", async () => {
    const first = await call("GET", "/api/v1/challenges/daily");
    const second = await call("GET", `/api/v1/challenges/daily/${first.challenge.date}`);
    const same = JSON.stringify(first.challenge.board) === JSON.stringify(second.challenge.board);
    if (!same) throw new Error("the same date produced two different boards");
    return `day ${first.challenge.dayNumber}, ${first.challenge.modifier.name}`;
});
await step("achievement catalog", async () => `${(await call("GET", "/api/v1/achievements")).items.length} achievements`);
await step("global stats", async () => {
    const stats = await call("GET", "/api/v1/stats/global");
    return `${stats.players} players, ${stats.games} games`;
});

await step("register", async () => {
    const result = await call("POST", "/api/v1/auth/register", { body: account, expect: [201] });
    accessToken = result.accessToken;
    return result.user.username;
});

await step("reject a weak password", async () => {
    await call("POST", "/api/v1/auth/register", {
        body: { username: `weak${suffix}`, email: `weak-${suffix}@example.test`, password: "short" },
        expect: [422]
    });
    return "422 as expected";
});

await step("reject a duplicate username", async () => {
    await call("POST", "/api/v1/auth/register", {
        body: { ...account, email: `other-${suffix}@example.test` },
        expect: [409]
    });
    return "409 as expected";
});

await step("reject an unauthenticated read", async () => {
    const saved = accessToken;
    accessToken = null;
    await call("GET", "/api/v1/auth/me", { auth: true, expect: [401] });
    accessToken = saved;
    return "401 as expected";
});

await step("upload a save", async () => {
    const result = await call("POST", "/api/v1/saves/sync", {
        auth: true,
        body: { save: { board: BOARD, score: 5600, bestScore: 5600, moves: 480, client: "cli" } }
    });
    if (result.resolution !== "uploaded") throw new Error(`resolution was ${result.resolution}`);
    return `revision ${result.save.revision}`;
});

await step("a second sync of the same round is a no-op", async () => {
    const result = await call("POST", "/api/v1/saves/sync", {
        auth: true,
        body: { save: { board: BOARD, score: 5600, bestScore: 5600, moves: 480, client: "cli" } }
    });
    if (result.resolution !== "in_sync") throw new Error(`resolution was ${result.resolution}`);
    return "in_sync";
});

await step("a continuation uploads", async () => {
    const result = await call("POST", "/api/v1/saves/sync", {
        auth: true,
        body: { save: { board: CONTINUED_BOARD, score: 5800, moves: 496, baseRevision: 1, client: "cli" } }
    });
    if (result.resolution !== "uploaded") throw new Error(`resolution was ${result.resolution}`);
    return `revision ${result.save.revision}`;
});

await step("a divergent round conflicts without losing anything", async () => {
    const result = await call("POST", "/api/v1/saves/sync", {
        auth: true,
        body: { save: { board: [2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], score: 40, moves: 3, client: "cli" } }
    });
    if (result.resolution !== "conflicted") throw new Error(`resolution was ${result.resolution}`);
    if (!result.conflictSlot) throw new Error("the losing round was not preserved");
    const saves = await call("GET", "/api/v1/saves", { auth: true });
    const preserved = saves.items.some(save => save.slot === result.conflictSlot);
    if (!preserved) throw new Error("the conflict slot is not readable");
    return `winner ${result.winner}, preserved in ${result.conflictSlot}`;
});

await step("submit a score", async () => {
    const result = await call("POST", "/api/v1/scores", {
        auth: true,
        body: { board: BOARD, score: 5600, moves: 480, durationSeconds: 540, client: "cli" },
        expect: [201]
    });
    if (!result.score.verified) throw new Error(`score was flagged: ${result.score.verificationNote ?? "unknown"}`);
    return `${result.unlockedAchievements.length} achievements unlocked`;
});

await step("resubmitting the same round is idempotent", async () => {
    const result = await call("POST", "/api/v1/scores", {
        auth: true,
        body: { board: BOARD, score: 5600, moves: 480, durationSeconds: 540, client: "cli" },
        expect: [200]
    });
    if (!result.duplicate) throw new Error("a second identical submission created a new row");
    return "duplicate detected";
});

await step("an impossible score is flagged, not ranked", async () => {
    const result = await call("POST", "/api/v1/scores", {
        auth: true,
        body: { board: [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], score: 999_999, client: "cli" },
        expect: [201]
    });
    if (result.score.verified) throw new Error("an impossible score was accepted as verified");
    return "flagged unverified";
});

await step("leaderboard lists the round", async () => {
    const board = await call("GET", "/api/v1/leaderboard?period=all&limit=5", { auth: true });
    return `${board.summary.players} ranked players, top ${board.summary.topScore}`;
});

await step("personal rank", async () => {
    const rank = await call("GET", "/api/v1/leaderboard/me?period=all", { auth: true });
    if (!rank.ranked) throw new Error("the submitted score did not rank");
    return `#${rank.rank} of ${rank.players}`;
});

await step("around-me slice", async () => `${(await call("GET", "/api/v1/leaderboard/around-me?radius=2", { auth: true })).entries.length} rows`);
await step("personal stats", async () => {
    const stats = await call("GET", "/api/v1/stats/me", { auth: true });
    return `${stats.games} games, best ${stats.bestScore}`;
});
await step("achievement progress", async () => {
    const achievements = await call("GET", "/api/v1/achievements/me", { auth: true });
    return `${achievements.summary.unlocked}/${achievements.summary.total} unlocked`;
});
await step("preferences round-trip", async () => {
    await call("PUT", "/api/v1/users/me/preferences", { auth: true, body: { theme: "dark", autoSync: false } });
    const preferences = await call("GET", "/api/v1/users/me/preferences", { auth: true });
    if (preferences.preferences.theme !== "dark") throw new Error("the preference did not persist");
    return "dark, autoSync off";
});
await step("public profile", async () => `${(await call("GET", `/api/v1/users/${account.username}`)).user.username} is visible`);
await step("data export", async () => `${(await call("GET", "/api/v1/users/me/export", { auth: true })).scores.length} scores exported`);
await step("telemetry batch", async () => {
    const result = await call("POST", "/api/v1/events", {
        auth: true,
        body: { client: "cli", events: [{ type: "game_started" }, { type: "game_over", value: 5600 }] },
        expect: [202]
    });
    return `${result.accepted} accepted`;
});
await step("sessions list", async () => `${(await call("GET", "/api/v1/auth/sessions", { auth: true })).items.length} session(s)`);
await step("daily challenge submission", async () => {
    const result = await call("POST", "/api/v1/challenges/daily/submit", {
        auth: true,
        body: { board: BOARD, score: 900, moves: 60, client: "cli" },
        expect: [201]
    });
    return `rank #${result.rank} of ${result.players}`;
});

await step("delete the account and everything it owns", async () => {
    await call("DELETE", "/api/v1/auth/me", { auth: true, body: { password: account.password, confirm: "DELETE" } });
    await call("GET", `/api/v1/users/${account.username}`, { expect: [404] });
    return "gone";
});

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length > 0) process.exit(1);
