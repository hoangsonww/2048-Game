/**
 * The achievement catalog and the evaluator that awards from it.
 *
 * Definitions live in code, not in the database. An achievement is behaviour —
 * it decides when a player earns something — and behaviour that lives in a
 * document is behaviour no test covers and no review sees. Only the unlock is
 * data.
 *
 * Every rule is a pure function of `(context)`, which is what lets the whole
 * catalog be tested without a database.
 */
import { UserAchievement } from "../models/UserAchievement.js";

/**
 * @typedef {object} EvaluationContext
 * @property {number} score Score of the round being submitted.
 * @property {number} highestTile Highest tile on the final board.
 * @property {number} moves Moves played in the round.
 * @property {number} durationSeconds Wall-clock length of the round.
 * @property {boolean} won Whether the round reached 2048.
 * @property {object} statistics The player's career totals *after* this round.
 */

/** @type {ReadonlyArray<{key: string, name: string, description: string, category: string, points: number, target: (c: EvaluationContext) => number, progress: (c: EvaluationContext) => number}>} */
export const ACHIEVEMENTS = Object.freeze([
    {
        key: "first_game",
        name: "First Slide",
        description: "Finish your first round.",
        category: "milestone",
        points: 5,
        target: () => 1,
        progress: context => Math.min(1, context.statistics.gamesPlayed)
    },
    {
        key: "tile_128",
        name: "Getting Warm",
        description: "Build a 128 tile.",
        category: "tiles",
        points: 10,
        target: () => 128,
        progress: context => Math.min(128, context.statistics.highestTile)
    },
    {
        key: "tile_512",
        name: "Gold Standard",
        description: "Build a 512 tile.",
        category: "tiles",
        points: 20,
        target: () => 512,
        progress: context => Math.min(512, context.statistics.highestTile)
    },
    {
        key: "tile_1024",
        name: "Halfway There",
        description: "Build a 1024 tile.",
        category: "tiles",
        points: 30,
        target: () => 1024,
        progress: context => Math.min(1024, context.statistics.highestTile)
    },
    {
        key: "tile_2048",
        name: "2048",
        description: "Reach the 2048 tile.",
        category: "tiles",
        points: 60,
        target: () => 2048,
        progress: context => Math.min(2048, context.statistics.highestTile)
    },
    {
        key: "tile_4096",
        name: "Past the Post",
        description: "Keep playing past 2048 and build a 4096 tile.",
        category: "tiles",
        points: 100,
        target: () => 4096,
        progress: context => Math.min(4096, context.statistics.highestTile)
    },
    {
        key: "score_5000",
        name: "Five Thousand",
        description: "Finish a round with 5,000 points.",
        category: "score",
        points: 15,
        target: () => 5000,
        progress: context => Math.min(5000, context.statistics.bestScore)
    },
    {
        key: "score_20000",
        name: "Twenty Thousand",
        description: "Finish a round with 20,000 points.",
        category: "score",
        points: 40,
        target: () => 20_000,
        progress: context => Math.min(20_000, context.statistics.bestScore)
    },
    {
        key: "score_100000",
        name: "Six Figures Soon",
        description: "Finish a round with 100,000 points.",
        category: "score",
        points: 150,
        target: () => 100_000,
        progress: context => Math.min(100_000, context.statistics.bestScore)
    },
    {
        key: "games_10",
        name: "Regular",
        description: "Play ten rounds.",
        category: "dedication",
        points: 10,
        target: () => 10,
        progress: context => Math.min(10, context.statistics.gamesPlayed)
    },
    {
        key: "games_100",
        name: "Committed",
        description: "Play one hundred rounds.",
        category: "dedication",
        points: 50,
        target: () => 100,
        progress: context => Math.min(100, context.statistics.gamesPlayed)
    },
    {
        key: "wins_5",
        name: "Repeat Performance",
        description: "Reach 2048 in five separate rounds.",
        category: "dedication",
        points: 80,
        target: () => 5,
        progress: context => Math.min(5, context.statistics.gamesWon)
    },
    {
        key: "efficient_win",
        name: "Efficient",
        description: "Reach 2048 in 900 moves or fewer.",
        category: "skill",
        points: 90,
        target: () => 1,
        // Only a winning round can satisfy this, and only at submission time —
        // career totals cannot express "in one round", so the rule reads the
        // round rather than the statistics.
        progress: context => (context.won && context.moves > 0 && context.moves <= 900 ? 1 : 0)
    },
    {
        key: "speed_run",
        name: "Quick Hands",
        description: "Score 10,000 points in a round lasting under ten minutes.",
        category: "skill",
        points: 70,
        target: () => 1,
        progress: context => (context.score >= 10_000 && context.durationSeconds > 0 && context.durationSeconds <= 600 ? 1 : 0)
    },
    {
        key: "daily_player",
        name: "Daily Fixture",
        description: "Submit a score for the daily challenge.",
        category: "daily",
        points: 15,
        target: () => 1,
        progress: context => (context.mode === "daily" ? 1 : 0)
    }
]);

export const ACHIEVEMENT_KEYS = Object.freeze(ACHIEVEMENTS.map(entry => entry.key));

export function achievementCatalog() {
    return ACHIEVEMENTS.map(({ key, name, description, category, points }) => ({ key, name, description, category, points }));
}

export function findAchievement(key) {
    return ACHIEVEMENTS.find(entry => entry.key === key) ?? null;
}

/**
 * Computes the progress every achievement should have after a round.
 *
 * Progress is monotonic by construction: each rule reports an absolute value
 * derived from career totals or from the round itself, and the persistence step
 * only ever raises a stored value. A rule that returned a lower number than
 * last time therefore cannot un-award anything.
 *
 * @param {EvaluationContext} context
 */
export function evaluate(context) {
    return ACHIEVEMENTS.map(definition => {
        const target = definition.target(context);
        const progress = Math.max(0, Math.min(target, definition.progress(context)));
        return { key: definition.key, progress, target, satisfied: progress >= target };
    });
}

/**
 * Persists evaluated progress and returns only the achievements this call
 * unlocked, which is what the client needs to show a toast for.
 */
export async function applyAchievements(userId, context) {
    const evaluated = evaluate(context);
    const existing = await UserAchievement.find({ user: userId }).lean();
    const byKey = new Map(existing.map(entry => [entry.key, entry]));
    const operations = [];
    const unlocked = [];

    for (const result of evaluated) {
        const current = byKey.get(result.key);
        const alreadyUnlocked = Boolean(current?.unlockedAt);
        const previousProgress = current?.progress ?? 0;
        const progress = Math.max(previousProgress, result.progress);

        if (alreadyUnlocked && progress === previousProgress) continue;

        const justUnlocked = !alreadyUnlocked && progress >= result.target;
        operations.push({
            updateOne: {
                filter: { user: userId, key: result.key },
                update: {
                    $set: {
                        progress,
                        target: result.target,
                        ...(justUnlocked ? { unlockedAt: new Date() } : {})
                    },
                    $setOnInsert: { user: userId, key: result.key }
                },
                upsert: true
            }
        });

        if (justUnlocked) {
            const definition = findAchievement(result.key);
            unlocked.push({ key: definition.key, name: definition.name, description: definition.description, points: definition.points });
        }
    }

    if (operations.length > 0) {
        await UserAchievement.bulkWrite(operations, { ordered: false });
    }

    return unlocked;
}

/** Merges the catalog with a player's rows so unearned achievements still appear. */
export async function achievementsForUser(userId) {
    const rows = await UserAchievement.find({ user: userId }).lean();
    const byKey = new Map(rows.map(row => [row.key, row]));

    const items = ACHIEVEMENTS.map(definition => {
        const row = byKey.get(definition.key);
        const target = row?.target ?? definition.target({ statistics: {}, score: 0, highestTile: 0, moves: 0, durationSeconds: 0, won: false, mode: "classic" });
        return {
            key: definition.key,
            name: definition.name,
            description: definition.description,
            category: definition.category,
            points: definition.points,
            progress: row?.progress ?? 0,
            target,
            unlocked: Boolean(row?.unlockedAt),
            unlockedAt: row?.unlockedAt ?? null
        };
    });

    const earnedPoints = items.filter(item => item.unlocked).reduce((total, item) => total + item.points, 0);
    const totalPoints = items.reduce((total, item) => total + item.points, 0);

    return {
        items,
        summary: {
            unlocked: items.filter(item => item.unlocked).length,
            total: items.length,
            earnedPoints,
            totalPoints,
            completion: totalPoints === 0 ? 0 : Number(((earnedPoints / totalPoints) * 100).toFixed(1))
        }
    };
}

export default { ACHIEVEMENTS, achievementCatalog, findAchievement, evaluate, applyAchievements, achievementsForUser };
