/**
 * Leaderboard reads.
 *
 * Every board is an aggregation over the score collection. There is no
 * separately maintained ranking table, because a denormalised ranking is a
 * second source of truth that drifts the first time a score is deleted or
 * unverified — and a 4x4 puzzle's traffic does not need one.
 *
 * One board = one row per player, their best qualifying score in the window.
 * Showing three of the same player's rounds in the top ten is not a
 * leaderboard, it is a log.
 */
import mongoose from "mongoose";
import { Score } from "../models/Score.js";
import { Follow } from "../models/Follow.js";
import { User } from "../models/User.js";
import { periodWindow } from "../lib/http.js";

function matchStage({ period, mode, challengeDate, userIds, now }) {
    const window = periodWindow(period, now);
    const match = { verified: true, mode };
    if (window.since) match.createdAt = { $gte: window.since };
    if (challengeDate) match.challengeDate = challengeDate;
    if (userIds) match.user = { $in: userIds };
    return { match, window };
}

/**
 * Ties are broken by the earlier submission. Without an explicit tiebreak the
 * order of equal scores is whatever the index happens to return, which means a
 * player's rank can change between two identical requests — the kind of bug
 * that gets reported as "the leaderboard is flickering".
 */
const BEST_PER_PLAYER = [
    { $sort: { score: -1, createdAt: 1 } },
    {
        $group: {
            _id: "$user",
            score: { $first: "$score" },
            highestTile: { $first: "$highestTile" },
            moves: { $first: "$moves" },
            durationSeconds: { $first: "$durationSeconds" },
            won: { $first: "$won" },
            client: { $first: "$client" },
            username: { $first: "$username" },
            displayName: { $first: "$displayName" },
            country: { $first: "$country" },
            avatarColor: { $first: "$avatarColor" },
            achievedAt: { $first: "$createdAt" },
            entries: { $sum: 1 }
        }
    },
    { $sort: { score: -1, achievedAt: 1 } }
];

/**
 * Players who opted out are filtered *after* grouping rather than by excluding
 * their scores, so opting out hides the row without rewriting history — turning
 * the setting back on restores the same rank.
 */
const EXCLUDE_OPTED_OUT = [
    {
        $lookup: {
            from: User.collection.name,
            localField: "_id",
            foreignField: "_id",
            as: "profile",
            pipeline: [{ $project: { "preferences.showOnLeaderboard": 1, disabled: 1 } }]
        }
    },
    { $set: { profile: { $first: "$profile" } } },
    { $match: { "profile.preferences.showOnLeaderboard": { $ne: false }, "profile.disabled": { $ne: true } } },
    { $unset: "profile" }
];

function shapeRow(row, index, offset) {
    return {
        rank: offset + index + 1,
        userId: String(row._id),
        username: row.username,
        displayName: row.displayName || row.username,
        country: row.country ?? null,
        avatarColor: row.avatarColor ?? "#e96345",
        score: row.score,
        highestTile: row.highestTile,
        moves: row.moves,
        durationSeconds: row.durationSeconds,
        won: row.won,
        client: row.client,
        entries: row.entries,
        achievedAt: row.achievedAt
    };
}

/**
 * @param {object} options
 * @param {"daily"|"weekly"|"monthly"|"yearly"|"all"} options.period
 * @param {"classic"|"daily"} [options.mode]
 * @param {string|null} [options.challengeDate]
 * @param {number} options.limit
 * @param {number} options.offset
 * @param {mongoose.Types.ObjectId[]|null} [options.userIds] Restricts the board to a set of players.
 */
export async function leaderboardPage({ period, mode = "classic", challengeDate = null, limit, offset, userIds = null, now = new Date() }) {
    const { match, window } = matchStage({ period, mode, challengeDate, userIds, now });

    const [result] = await Score.aggregate([
        { $match: match },
        ...BEST_PER_PLAYER,
        ...EXCLUDE_OPTED_OUT,
        {
            $facet: {
                rows: [{ $skip: offset }, { $limit: limit }],
                total: [{ $count: "value" }],
                summary: [
                    {
                        $group: {
                            _id: null,
                            players: { $sum: 1 },
                            topScore: { $max: "$score" },
                            averageScore: { $avg: "$score" },
                            winners: { $sum: { $cond: ["$won", 1, 0] } }
                        }
                    }
                ]
            }
        }
    ]);

    const rows = result?.rows ?? [];
    const total = result?.total?.[0]?.value ?? 0;
    const summary = result?.summary?.[0] ?? { players: 0, topScore: 0, averageScore: 0, winners: 0 };

    return {
        entries: rows.map((row, index) => shapeRow(row, index, offset)),
        total,
        window,
        summary: {
            players: summary.players,
            topScore: summary.topScore ?? 0,
            averageScore: Math.round(summary.averageScore ?? 0),
            winners: summary.winners ?? 0
        }
    };
}

/**
 * A player's rank, computed by counting the players who beat them rather than
 * by paging the whole board — O(matched documents) in the server, one round
 * trip, and correct no matter how deep the player sits.
 */
export async function rankForUser({ userId, period, mode = "classic", challengeDate = null, now = new Date() }) {
    const objectId = new mongoose.Types.ObjectId(String(userId));
    const { match, window } = matchStage({ period, mode, challengeDate, userIds: null, now });

    const [result] = await Score.aggregate([
        { $match: match },
        ...BEST_PER_PLAYER,
        ...EXCLUDE_OPTED_OUT,
        {
            $facet: {
                mine: [{ $match: { _id: objectId } }],
                players: [{ $count: "value" }]
            }
        }
    ]);

    const mine = result?.mine?.[0];
    const players = result?.players?.[0]?.value ?? 0;
    if (!mine) {
        return { ranked: false, rank: null, players, window, entry: null, percentile: null };
    }

    // Counting the rows ahead is a second pass over the same grouped set. The
    // tiebreak must match the page ordering exactly — (score desc, achievedAt
    // asc) — or a player's rank will disagree with the row they see.
    const [aheadResult] = await Score.aggregate([
        { $match: match },
        ...BEST_PER_PLAYER,
        ...EXCLUDE_OPTED_OUT,
        {
            $match: {
                $or: [
                    { score: { $gt: mine.score } },
                    { score: mine.score, achievedAt: { $lt: mine.achievedAt } }
                ]
            }
        },
        { $count: "value" }
    ]);

    const rank = (aheadResult?.value ?? 0) + 1;

    return {
        ranked: true,
        rank,
        players,
        window,
        percentile: players > 0 ? Number((((players - rank + 1) / players) * 100).toFixed(1)) : null,
        entry: shapeRow(mine, 0, rank - 1)
    };
}

/** The slice of the board immediately around a player, for a "you are here" view. */
export async function neighbourhood({ userId, period, mode = "classic", radius = 3, now = new Date() }) {
    const position = await rankForUser({ userId, period, mode, now });
    if (!position.ranked) {
        const fallback = await leaderboardPage({ period, mode, limit: radius * 2 + 1, offset: 0, now });
        return { ...position, entries: fallback.entries, offset: 0 };
    }

    const offset = Math.max(0, position.rank - radius - 1);
    const page = await leaderboardPage({ period, mode, limit: radius * 2 + 1, offset, now });
    return { ...position, entries: page.entries, offset };
}

/** A board restricted to the people a player follows, plus the player. */
export async function friendsLeaderboard({ userId, period, limit, offset, now = new Date() }) {
    const edges = await Follow.find({ follower: userId }).select("following").lean();
    const userIds = [new mongoose.Types.ObjectId(String(userId)), ...edges.map(edge => edge.following)];
    return leaderboardPage({ period, mode: "classic", limit, offset, userIds, now });
}

export default { leaderboardPage, rankForUser, neighbourhood, friendsLeaderboard };
