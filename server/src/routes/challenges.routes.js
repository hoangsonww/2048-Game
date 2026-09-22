import express from "express";
import { Score } from "../models/Score.js";
import { requireAuth, optionalAuth } from "../middleware/auth.js";
import { asyncHandler, noStore, publicCache, requireFeature } from "../lib/http.js";
import { badRequest } from "../lib/errors.js";
import { boardSchema, clientSchema, isoDateSchema, paginationSchema, scoreValueSchema, validate, z } from "../lib/validate.js";
import { challengeForDate, isValidDateKey, todayKey } from "../services/daily-challenge.js";
import { leaderboardPage, rankForUser } from "../services/leaderboard.js";
import { submitScore } from "../services/scores.js";

const router = express.Router();
router.use(requireFeature("dailyChallenge"));

function challengeOrThrow(dateKey) {
    if (!isValidDateKey(dateKey)) throw badRequest("That is not a valid calendar date.");
    return challengeForDate(dateKey);
}

router.get(
    "/daily",
    optionalAuth,
    asyncHandler(async (req, res) => {
        const challenge = challengeForDate(todayKey());
        const attempted = req.user
            ? await Score.exists({ user: req.user._id, mode: "daily", challengeDate: challenge.date })
            : false;

        // The board is derived from the date, so the response is identical for
        // everyone until midnight UTC — except for `attempted`, which is why a
        // signed-in read is not shared-cached.
        if (req.user) noStore(res);
        else publicCache(res, 120);

        res.json({ challenge, attempted: Boolean(attempted) });
    })
);

router.get(
    "/daily/leaderboard",
    validate({ query: paginationSchema.extend({ date: isoDateSchema.optional() }) }),
    asyncHandler(async (req, res) => {
        const { limit, offset, date } = req.valid.query;
        const dateKey = date ?? todayKey();
        challengeOrThrow(dateKey);

        const page = await leaderboardPage({ period: "all", mode: "daily", challengeDate: dateKey, limit, offset });
        publicCache(res, 30).json({
            date: dateKey,
            entries: page.entries,
            summary: page.summary,
            pagination: { total: page.total, limit, offset, count: page.entries.length, hasMore: offset + page.entries.length < page.total }
        });
    })
);

router.get(
    "/daily/me",
    requireAuth,
    validate({ query: z.object({ date: isoDateSchema.optional() }) }),
    asyncHandler(async (req, res) => {
        const dateKey = req.valid.query.date ?? todayKey();
        challengeOrThrow(dateKey);
        noStore(res).json({
            date: dateKey,
            ...(await rankForUser({ userId: req.user._id, period: "all", mode: "daily", challengeDate: dateKey }))
        });
    })
);

router.post(
    "/daily/submit",
    requireAuth,
    validate({
        body: z.object({
            date: isoDateSchema.optional(),
            board: boardSchema.optional(),
            grid: boardSchema.optional(),
            score: scoreValueSchema,
            moves: z.number().int().min(0).max(1_000_000).default(0),
            durationSeconds: z.number().int().min(0).max(86_400).default(0),
            client: clientSchema
        }).refine(value => value.board ?? value.grid, { message: "Provide either `board` (16 cells) or `grid` (4x4)." })
    }),
    asyncHandler(async (req, res) => {
        const body = req.valid.body;
        const dateKey = body.date ?? todayKey();
        challengeOrThrow(dateKey);

        // Yesterday's challenge cannot be entered today. Without this the
        // "daily" board becomes a backlog anyone can grind through.
        if (dateKey !== todayKey()) throw badRequest("Only today's challenge accepts submissions.");

        const result = await submitScore({
            user: req.user,
            board: body.board ?? body.grid,
            score: body.score,
            moves: body.moves,
            durationSeconds: body.durationSeconds,
            mode: "daily",
            challengeDate: dateKey,
            client: body.client
        });

        const rank = await rankForUser({ userId: req.user._id, period: "all", mode: "daily", challengeDate: dateKey });

        noStore(res).status(result.duplicate ? 200 : 201).json({
            date: dateKey,
            score: result.score.toJSON(),
            duplicate: result.duplicate,
            unlockedAchievements: result.unlockedAchievements,
            rank: rank.rank,
            players: rank.players
        });
    })
);

router.get(
    "/daily/:date",
    validate({ params: z.object({ date: isoDateSchema }) }),
    asyncHandler(async (req, res) => {
        publicCache(res, 3600).json({ challenge: challengeOrThrow(req.valid.params.date) });
    })
);

export default router;
