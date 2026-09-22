import assert from "node:assert/strict";
import test from "node:test";
import { ACHIEVEMENTS, achievementCatalog, evaluate, findAchievement } from "../../src/services/achievements.js";

function context(overrides = {}) {
    return {
        score: 0,
        highestTile: 0,
        moves: 0,
        durationSeconds: 0,
        won: false,
        mode: "classic",
        statistics: { bestScore: 0, gamesPlayed: 0, gamesWon: 0, highestTile: 0 },
        ...overrides
    };
}

function result(evaluated, key) {
    return evaluated.find(entry => entry.key === key);
}

test("every catalog entry is well formed and uniquely keyed", () => {
    const keys = new Set();
    for (const achievement of ACHIEVEMENTS) {
        assert.ok(achievement.key, "an achievement needs a key");
        assert.equal(keys.has(achievement.key), false, `duplicate key ${achievement.key}`);
        keys.add(achievement.key);
        assert.ok(achievement.name.length > 0, `${achievement.key} needs a name`);
        assert.ok(achievement.description.length > 10, `${achievement.key} needs a real description`);
        assert.ok(achievement.points > 0, `${achievement.key} needs to be worth something`);
    }
});

test("the public catalog does not leak the rule functions", () => {
    for (const entry of achievementCatalog()) {
        assert.deepEqual(Object.keys(entry).sort(), ["category", "description", "key", "name", "points"]);
    }
});

test("a fresh player has unlocked nothing", () => {
    for (const entry of evaluate(context())) {
        assert.equal(entry.satisfied, false, `${entry.key} should not be satisfied on a blank slate`);
    }
});

test("finishing one round unlocks the first-game achievement and nothing else", () => {
    const evaluated = evaluate(context({ statistics: { bestScore: 40, gamesPlayed: 1, gamesWon: 0, highestTile: 8 } }));
    assert.equal(result(evaluated, "first_game").satisfied, true);
    assert.equal(result(evaluated, "tile_128").satisfied, false);
    assert.equal(result(evaluated, "games_10").satisfied, false);
});

test("tile achievements unlock at their threshold, not before", () => {
    const below = evaluate(context({ statistics: { highestTile: 1024, gamesPlayed: 1, bestScore: 0, gamesWon: 0 } }));
    assert.equal(result(below, "tile_1024").satisfied, true);
    assert.equal(result(below, "tile_2048").satisfied, false, "1024 is not 2048");

    const at = evaluate(context({ statistics: { highestTile: 2048, gamesPlayed: 1, bestScore: 0, gamesWon: 0 } }));
    assert.equal(result(at, "tile_2048").satisfied, true);
});

test("progress is clamped to the target so a huge career cannot overshoot", () => {
    const evaluated = evaluate(context({ statistics: { highestTile: 131_072, bestScore: 5_000_000, gamesPlayed: 9999, gamesWon: 900 } }));
    for (const entry of evaluated) {
        assert.ok(entry.progress <= entry.target, `${entry.key} reported ${entry.progress}/${entry.target}`);
    }
});

test("the efficient-win achievement reads the round, not the career", () => {
    // Career totals cannot express "in one round", which is exactly why this
    // rule looks at the submission instead.
    const efficient = evaluate(context({ won: true, moves: 850, statistics: { highestTile: 2048, gamesPlayed: 1, gamesWon: 1, bestScore: 20_000 } }));
    assert.equal(result(efficient, "efficient_win").satisfied, true);

    const grindy = evaluate(context({ won: true, moves: 1500, statistics: { highestTile: 2048, gamesPlayed: 1, gamesWon: 1, bestScore: 20_000 } }));
    assert.equal(result(grindy, "efficient_win").satisfied, false);

    const lost = evaluate(context({ won: false, moves: 400, statistics: { highestTile: 512, gamesPlayed: 1, gamesWon: 0, bestScore: 4000 } }));
    assert.equal(result(lost, "efficient_win").satisfied, false, "a round that never reached 2048 cannot be an efficient win");
});

test("a zero-move round cannot satisfy the efficiency rules", () => {
    // Guarding the lower bound matters: `moves <= 900` alone would award the
    // achievement to a round that reported no moves at all.
    const evaluated = evaluate(context({ won: true, moves: 0, statistics: { highestTile: 2048, gamesPlayed: 1, gamesWon: 1, bestScore: 20_000 } }));
    assert.equal(result(evaluated, "efficient_win").satisfied, false);

    const speedy = evaluate(context({ score: 12_000, durationSeconds: 0 }));
    assert.equal(result(speedy, "speed_run").satisfied, false);
});

test("the speed-run achievement needs both the score and the clock", () => {
    assert.equal(result(evaluate(context({ score: 12_000, durationSeconds: 480 })), "speed_run").satisfied, true);
    assert.equal(result(evaluate(context({ score: 12_000, durationSeconds: 900 })), "speed_run").satisfied, false, "too slow");
    assert.equal(result(evaluate(context({ score: 9000, durationSeconds: 300 })), "speed_run").satisfied, false, "too few points");
});

test("the daily achievement only fires for a daily submission", () => {
    assert.equal(result(evaluate(context({ mode: "daily" })), "daily_player").satisfied, true);
    assert.equal(result(evaluate(context({ mode: "classic" })), "daily_player").satisfied, false);
});

test("findAchievement resolves a known key and refuses an unknown one", () => {
    assert.equal(findAchievement("tile_2048").name, "2048");
    assert.equal(findAchievement("not_a_real_key"), null);
});
