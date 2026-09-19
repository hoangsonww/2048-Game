import express from "express";
import { User } from "../models/User.js";
import { optionalAuth, requireAuth } from "../middleware/auth.js";
import { asyncHandler, noStore, periodWindow, publicCache, requireFeature } from "../lib/http.js";
import { notFound } from "../lib/errors.js";
import { paginationSchema, periodSchema, usernameSchema, validate, z } from "../lib/validate.js";
import { friendsLeaderboard, leaderboardPage, neighbourhood, rankForUser } from "../services/leaderboard.js";

const router = express.Router();
router.use(requireFeature("leaderboards"));

const boardQuery = paginationSchema.extend({
    period: periodSchema,
    mode: z.enum(["classic", "daily"]).default("classic"),
    challengeDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
});

router.get(
    "/periods",
    asyncHandler(async (_req, res) => {
        const now = new Date();
        publicCache(res, 300).json({
            // Windows are UTC, and the boundaries are returned rather than
            // described so a client never has to reimplement the rule.
            timezone: "UTC",
            periods: ["daily", "weekly", "monthly", "yearly", "all"].map(period => periodWindow(period, now))
        });
    })
);

router.get(
    "/",
    optionalAuth,
    validate({ query: boardQuery }),
    asyncHandler(async (req, res) => {
        const { limit, offset, period, mode, challengeDate } = req.valid.query;
        const page = await leaderboardPage({ period, mode, challengeDate: challengeDate ?? null, limit, offset });

        const viewerId = req.user ? String(req.user._id) : null;
        const entries = page.entries.map(entry => ({ ...entry, isViewer: viewerId === entry.userId }));

        // Public and cacheable, but only for signed-out readers: a personalised
        // `isViewer` flag must never be served from a shared cache.
        if (viewerId) noStore(res);
        else publicCache(res, 30);

        res.json({
            entries,
            summary: page.summary,
            window: page.window,
            pagination: { total: page.total, limit, offset, count: entries.length, hasMore: offset + entries.length < page.total }
        });
    })
);

router.get(
    "/me",
    requireAuth,
    validate({ query: z.object({ period: periodSchema, mode: z.enum(["classic", "daily"]).default("classic") }) }),
    asyncHandler(async (req, res) => {
        const { period, mode } = req.valid.query;
        noStore(res).json(await rankForUser({ userId: req.user._id, period, mode }));
    })
);

router.get(
    "/around-me",
    requireAuth,
    validate({
        query: z.object({
            period: periodSchema,
            mode: z.enum(["classic", "daily"]).default("classic"),
            radius: z.coerce.number().int().min(1).max(25).default(4)
        })
    }),
    asyncHandler(async (req, res) => {
        const { period, mode, radius } = req.valid.query;
        const result = await neighbourhood({ userId: req.user._id, period, mode, radius });
        noStore(res).json({
            ...result,
            entries: result.entries.map(entry => ({ ...entry, isViewer: entry.userId === String(req.user._id) }))
        });
    })
);

router.get(
    "/friends",
    requireAuth,
    validate({ query: paginationSchema.extend({ period: periodSchema }) }),
    asyncHandler(async (req, res) => {
        const { limit, offset, period } = req.valid.query;
        const page = await friendsLeaderboard({ userId: req.user._id, period, limit, offset });
        noStore(res).json({
            entries: page.entries.map(entry => ({ ...entry, isViewer: entry.userId === String(req.user._id) })),
            summary: page.summary,
            window: page.window,
            pagination: { total: page.total, limit, offset, count: page.entries.length, hasMore: offset + page.entries.length < page.total }
        });
    })
);

router.get(
    "/users/:username",
    validate({
        params: z.object({ username: usernameSchema }),
        query: z.object({ period: periodSchema, mode: z.enum(["classic", "daily"]).default("classic") })
    }),
    asyncHandler(async (req, res) => {
        const user = await User.findOne({ usernameLower: req.valid.params.username.toLowerCase() });
        if (!user) throw notFound("Player");
        const { period, mode } = req.valid.query;
        publicCache(res, 30).json(await rankForUser({ userId: user._id, period, mode }));
    })
);

export default router;
