import assert from "node:assert/strict";
import test from "node:test";
import { boardForDate, challengeForDate, isValidDateKey, mulberry32, seedForDate, todayKey } from "../../src/services/daily-challenge.js";
import { isValidBoard } from "../../src/lib/game-rules.js";

test("the same date always produces the same board", () => {
    // This is the whole feature. If it ever stops holding, two players are not
    // playing the same challenge and the daily leaderboard means nothing.
    assert.deepEqual(boardForDate("2026-09-18"), boardForDate("2026-09-18"));
    assert.deepEqual(challengeForDate("2026-09-18"), challengeForDate("2026-09-18"));
});

test("different dates produce different boards", () => {
    const seen = new Set();
    for (let day = 1; day <= 28; day += 1) {
        seen.add(boardForDate(`2026-02-${String(day).padStart(2, "0")}`).join(","));
    }
    assert.ok(seen.size >= 20, `expected varied openings across a month, saw ${seen.size} distinct boards`);
});

test("a generated opening is a legal board with exactly two tiles", () => {
    for (const date of ["2024-01-01", "2025-06-15", "2026-09-18", "2030-12-31"]) {
        const board = boardForDate(date);
        assert.equal(isValidBoard(board), true, `${date} produced an invalid board`);
        const tiles = board.filter(value => value !== 0);
        assert.equal(tiles.length, 2, `${date} placed ${tiles.length} tiles`);
        for (const tile of tiles) assert.ok(tile === 2 || tile === 4, `${date} spawned a ${tile}`);
    }
});

test("mulberry32 is deterministic and stays in [0, 1)", () => {
    const first = mulberry32(12_345);
    const second = mulberry32(12_345);
    for (let index = 0; index < 500; index += 1) {
        const value = first();
        assert.equal(value, second(), "two generators with one seed must not diverge");
        assert.ok(value >= 0 && value < 1, `value ${value} left the unit interval`);
    }
});

test("the seed is a stable 32-bit hash of the date string", () => {
    const seed = seedForDate("2026-09-18");
    assert.equal(seed, seedForDate("2026-09-18"));
    assert.ok(Number.isInteger(seed) && seed >= 0 && seed < 2 ** 32);
    assert.notEqual(seed, seedForDate("2026-09-19"), "adjacent dates must not collide");
});

test("date keys are validated against the calendar, not just the shape", () => {
    assert.equal(isValidDateKey("2026-09-18"), true);
    assert.equal(isValidDateKey("2026-02-30"), false, "February has no thirtieth");
    assert.equal(isValidDateKey("2026-13-01"), false);
    assert.equal(isValidDateKey("26-09-18"), false);
    assert.equal(isValidDateKey("not-a-date"), false);
});

test("a challenge carries everything a client needs to reproduce it offline", () => {
    const challenge = challengeForDate("2026-09-18");
    assert.equal(challenge.date, "2026-09-18");
    assert.ok(challenge.dayNumber > 0);
    assert.ok(Number.isInteger(challenge.seed));
    assert.ok(challenge.modifier.key.length > 0);
    assert.equal(challenge.expiresAt.toISOString(), "2026-09-19T00:00:00.000Z", "a challenge expires at the next UTC midnight");
});

test("todayKey is the UTC day", () => {
    assert.equal(todayKey(new Date("2026-09-18T23:59:59.999Z")), "2026-09-18");
    assert.equal(todayKey(new Date("2026-09-19T00:00:00.000Z")), "2026-09-19");
});
