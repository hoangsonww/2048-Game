/**
 * Aggregate statistics.
 *
 * Everything here is derived at read time from the score collection. The
 * numbers are therefore always consistent with the rounds that produced them,
 * which is the property that matters more than the milliseconds a cached
 * counter would save at this scale.
 */
import mongoose from "mongoose";
import { Score } from "../models/Score.js";
import { User } from "../models/User.js";
import { GameSave } from "../models/GameSave.js";
import { periodWindow } from "../lib/http.js";

export async function globalStats({ now = new Date() } = {}) {
    const [totals] = await Score.aggregate([
        { $match: { verified: true } },
        {
            $group: {
                _id: null,
                games: { $sum: 1 },
                totalScore: { $sum: "$score" },
                averageScore: { $avg: "$score" },
                topScore: { $max: "$score" },
                wins: { $sum: { $cond: ["$won", 1, 0] } },
                totalMoves: { $sum: "$moves" },
                highestTile: { $max: "$highestTile" }
            }
        }
    ]);

    const since = periodWindow("daily", now).since;
    const [players, activeToday, gamesToday, savedRounds] = await Promise.all([
        User.countDocuments({ disabled: { $ne: true } }),
        User.countDocuments({ lastSeenAt: { $gte: since } }),
        Score.countDocuments({ verified: true, createdAt: { $gte: since } }),
        GameSave.estimatedDocumentCount()
    ]);

    const games = totals?.games ?? 0;
    return {
        players,
        activeToday,
        games,
        gamesToday,
        savedRounds,
        wins: totals?.wins ?? 0,
        winRate: games > 0 ? Number((((totals?.wins ?? 0) / games) * 100).toFixed(2)) : 0,
        topScore: totals?.topScore ?? 0,
        averageScore: Math.round(totals?.averageScore ?? 0),
        totalScore: totals?.totalScore ?? 0,
        totalMoves: totals?.totalMoves ?? 0,
        highestTile: totals?.highestTile ?? 0,
        generatedAt: now
    };
}

export async function tileDistribution({ userId = null } = {}) {
    const match = { verified: true };
    if (userId) match.user = new mongoose.Types.ObjectId(String(userId));

    const rows = await Score.aggregate([
        { $match: match },
        { $group: { _id: "$highestTile", games: { $sum: 1 }, bestScore: { $max: "$score" } } },
        { $sort: { _id: 1 } }
    ]);

    const games = rows.reduce((total, row) => total + row.games, 0);
    return {
        games,
        buckets: rows.map(row => ({
            tile: row._id,
            games: row.games,
            bestScore: row.bestScore,
            share: games > 0 ? Number(((row.games / games) * 100).toFixed(2)) : 0
        }))
    };
}

/**
 * A dense daily series: days with no games are emitted as zeroes rather than
 * omitted, because a sparse series drawn as a line chart silently rewrites the
 * x-axis and makes a quiet week look like a busy one.
 */
export async function activitySeries({ userId = null, days = 30, now = new Date() } = {}) {
    const start = new Date(now);
    start.setUTCHours(0, 0, 0, 0);
    start.setUTCDate(start.getUTCDate() - (days - 1));

    const match = { verified: true, createdAt: { $gte: start } };
    if (userId) match.user = new mongoose.Types.ObjectId(String(userId));

    const rows = await Score.aggregate([
        { $match: match },
        {
            $group: {
                _id: { $dateToString: { format: "%Y-%m-%d", date: "$createdAt", timezone: "UTC" } },
                games: { $sum: 1 },
                bestScore: { $max: "$score" },
                totalScore: { $sum: "$score" },
                wins: { $sum: { $cond: ["$won", 1, 0] } }
            }
        }
    ]);

    const byDay = new Map(rows.map(row => [row._id, row]));
    const series = [];
    for (let offset = 0; offset < days; offset += 1) {
        const day = new Date(start);
        day.setUTCDate(start.getUTCDate() + offset);
        const key = day.toISOString().slice(0, 10);
        const row = byDay.get(key);
        series.push({
            date: key,
            games: row?.games ?? 0,
            bestScore: row?.bestScore ?? 0,
            totalScore: row?.totalScore ?? 0,
            wins: row?.wins ?? 0
        });
    }

    return { days, since: start, series };
}

export async function personalStats({ userId, now = new Date() }) {
    const objectId = new mongoose.Types.ObjectId(String(userId));

    const [aggregate] = await Score.aggregate([
        { $match: { user: objectId, verified: true } },
        {
            $group: {
                _id: null,
                games: { $sum: 1 },
                bestScore: { $max: "$score" },
                averageScore: { $avg: "$score" },
                totalScore: { $sum: "$score" },
                totalMoves: { $sum: "$moves" },
                totalSeconds: { $sum: "$durationSeconds" },
                wins: { $sum: { $cond: ["$won", 1, 0] } },
                highestTile: { $max: "$highestTile" },
                firstGameAt: { $min: "$createdAt" },
                lastGameAt: { $max: "$createdAt" }
            }
        }
    ]);

    const [tiles, activity, recent] = await Promise.all([
        tileDistribution({ userId }),
        activitySeries({ userId, days: 30, now }),
        Score.find({ user: objectId }).sort({ createdAt: -1 }).limit(5).lean()
    ]);

    const games = aggregate?.games ?? 0;
    return {
        games,
        wins: aggregate?.wins ?? 0,
        winRate: games > 0 ? Number((((aggregate?.wins ?? 0) / games) * 100).toFixed(2)) : 0,
        bestScore: aggregate?.bestScore ?? 0,
        averageScore: Math.round(aggregate?.averageScore ?? 0),
        totalScore: aggregate?.totalScore ?? 0,
        totalMoves: aggregate?.totalMoves ?? 0,
        totalPlaytimeSeconds: aggregate?.totalSeconds ?? 0,
        highestTile: aggregate?.highestTile ?? 0,
        averageMovesPerGame: games > 0 ? Math.round((aggregate?.totalMoves ?? 0) / games) : 0,
        pointsPerMove: (aggregate?.totalMoves ?? 0) > 0 ? Number(((aggregate?.totalScore ?? 0) / aggregate.totalMoves).toFixed(2)) : 0,
        firstGameAt: aggregate?.firstGameAt ?? null,
        lastGameAt: aggregate?.lastGameAt ?? null,
        tiles,
        activity,
        recentGames: recent.map(row => ({
            id: String(row._id),
            score: row.score,
            highestTile: row.highestTile,
            moves: row.moves,
            won: row.won,
            mode: row.mode,
            createdAt: row.createdAt
        }))
    };
}

export default { globalStats, personalStats, tileDistribution, activitySeries };
