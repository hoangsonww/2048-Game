import assert from "node:assert/strict";
import test from "node:test";
import { collection, periodWindow, utcDayKey } from "../../src/lib/http.js";

const WEDNESDAY = new Date("2026-09-16T13:45:12.000Z");
const SUNDAY = new Date("2026-09-20T01:00:00.000Z");

test("the daily window starts at UTC midnight", () => {
    const window = periodWindow("daily", WEDNESDAY);
    assert.equal(window.since.toISOString(), "2026-09-16T00:00:00.000Z");
    assert.equal(window.until.toISOString(), WEDNESDAY.toISOString());
});

test("the weekly window starts on Monday, not Sunday", () => {
    // getUTCDay() makes Sunday 0, so a naive implementation rolls the week
    // over on the wrong day and a Sunday evening run lands in next week.
    assert.equal(periodWindow("weekly", WEDNESDAY).since.toISOString(), "2026-09-14T00:00:00.000Z");
    assert.equal(periodWindow("weekly", SUNDAY).since.toISOString(), "2026-09-14T00:00:00.000Z", "Sunday belongs to the week that began on Monday");
});

test("monthly and yearly windows start at the first instant of the period", () => {
    assert.equal(periodWindow("monthly", WEDNESDAY).since.toISOString(), "2026-09-01T00:00:00.000Z");
    assert.equal(periodWindow("yearly", WEDNESDAY).since.toISOString(), "2026-01-01T00:00:00.000Z");
});

test("the all-time window is unbounded", () => {
    assert.deepEqual(periodWindow("all", WEDNESDAY), { period: "all", since: null, until: null });
    assert.deepEqual(periodWindow("nonsense", WEDNESDAY), { period: "all", since: null, until: null }, "an unknown period falls back to all-time rather than throwing");
});

test("periodWindow does not mutate the clock it was handed", () => {
    const now = new Date("2026-09-16T13:45:12.000Z");
    periodWindow("monthly", now);
    assert.equal(now.toISOString(), "2026-09-16T13:45:12.000Z");
});

test("utcDayKey is the ISO date in UTC", () => {
    assert.equal(utcDayKey(new Date("2026-09-16T23:59:59.999Z")), "2026-09-16");
});

test("the collection envelope reports whether more rows exist", () => {
    const firstPage = collection([1, 2, 3], { total: 10, limit: 3, offset: 0 });
    assert.deepEqual(firstPage.pagination, { total: 10, limit: 3, offset: 0, count: 3, hasMore: true });

    const lastPage = collection([10], { total: 10, limit: 3, offset: 9 });
    assert.equal(lastPage.pagination.hasMore, false);

    const empty = collection([], { total: 0, limit: 25, offset: 0 });
    assert.equal(empty.pagination.hasMore, false);
});
