import express from "express";
import { User } from "../models/User.js";
import { Score } from "../models/Score.js";
import { requireAuth, optionalAuth } from "../middleware/auth.js";
import { asyncHandler, collection, noStore, publicCache } from "../lib/http.js";
import { forbidden, notFound } from "../lib/errors.js";
import { paginationSchema, usernameSchema, validate, z } from "../lib/validate.js";
import { achievementsForUser } from "../services/achievements.js";
import { personalStats } from "../services/stats.js";

const router = express.Router();

/**
 * `me` routes are declared before `:username` on purpose. Express matches in
 * declaration order, so the reverse would make a player called "me"
 * unreachable and would route every `/me` request into a profile lookup.
 */
const preferencesSchema = z
    .object({
        theme: z.enum(["system", "light", "dark"]).optional(),
        reducedMotion: z.boolean().optional(),
        soundEnabled: z.boolean().optional(),
        hapticsEnabled: z.boolean().optional(),
        autoSync: z.boolean().optional(),
        publicProfile: z.boolean().optional(),
        showOnLeaderboard: z.boolean().optional()
    })
    .strict();

router.get(
    "/me/preferences",
    requireAuth,
    asyncHandler(async (req, res) => {
        noStore(res).json({ preferences: req.user.preferences });
    })
);

router.put(
    "/me/preferences",
    requireAuth,
    validate({ body: preferencesSchema }),
    asyncHandler(async (req, res) => {
        req.user.preferences = { ...req.user.preferences.toObject(), ...req.valid.body };
        await req.user.save();
        noStore(res).json({ preferences: req.user.preferences });
    })
);

router.get(
    "/me/export",
    requireAuth,
    asyncHandler(async (req, res) => {
        // A player can take everything with them. This is the counterpart to
        // account deletion and exists for the same reason: data about someone
        // should be theirs to read and theirs to remove.
        const [scores, achievements, statistics] = await Promise.all([
            Score.find({ user: req.user._id }).sort({ createdAt: -1 }).lean(),
            achievementsForUser(req.user._id),
            personalStats({ userId: req.user._id })
        ]);

        noStore(res)
            .set("Content-Disposition", `attachment; filename="2048-export-${req.user.username}.json"`)
            .json({
                exportedAt: new Date().toISOString(),
                account: req.user.toPrivateJSON(),
                statistics,
                achievements: achievements.items,
                scores: scores.map(score => ({
                    id: String(score._id),
                    score: score.score,
                    highestTile: score.highestTile,
                    moves: score.moves,
                    durationSeconds: score.durationSeconds,
                    won: score.won,
                    mode: score.mode,
                    board: score.board,
                    createdAt: score.createdAt
                }))
            });
    })
);

router.get(
    "/",
    validate({
        query: paginationSchema.extend({
            q: z.string().trim().min(1).max(40).optional(),
            sort: z.enum(["best", "recent", "name"]).default("best")
        })
    }),
    asyncHandler(async (req, res) => {
        const { limit, offset, q, sort } = req.valid.query;
        const filter = { disabled: { $ne: true }, "preferences.publicProfile": { $ne: false } };
        if (q) {
            // Anchored prefix match so the query can use the username index;
            // an unanchored regex would be a collection scan on every keystroke.
            const escaped = q.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            filter.usernameLower = new RegExp(`^${escaped}`);
        }

        const order = { best: { "statistics.bestScore": -1 }, recent: { createdAt: -1 }, name: { usernameLower: 1 } }[sort];
        const [users, total] = await Promise.all([
            User.find(filter).sort(order).skip(offset).limit(limit),
            User.countDocuments(filter)
        ]);

        publicCache(res, 30).json(collection(users.map(user => user.toPublicJSON()), { total, limit, offset }));
    })
);

async function loadProfile(username) {
    const user = await User.findOne({ usernameLower: username.toLowerCase() });
    if (!user || user.disabled) throw notFound("Player");
    return user;
}

router.get(
    "/:username",
    optionalAuth,
    validate({ params: z.object({ username: usernameSchema }) }),
    asyncHandler(async (req, res) => {
        const user = await loadProfile(req.valid.params.username);
        const isSelf = req.user && String(req.user._id) === String(user._id);
        noStore(res).json({ user: isSelf ? user.toPrivateJSON() : user.toPublicJSON(), isSelf: Boolean(isSelf) });
    })
);

router.get(
    "/:username/scores",
    validate({ params: z.object({ username: usernameSchema }), query: paginationSchema })
    ,
    asyncHandler(async (req, res) => {
        const user = await loadProfile(req.valid.params.username);
        if (user.preferences?.publicProfile === false) throw forbidden("That player's profile is private.");

        const { limit, offset } = req.valid.query;
        const filter = { user: user._id, verified: true };
        const [items, total] = await Promise.all([
            Score.find(filter).sort({ score: -1, createdAt: 1 }).skip(offset).limit(limit),
            Score.countDocuments(filter)
        ]);

        publicCache(res, 30).json(collection(items.map(item => item.toJSON()), { total, limit, offset }));
    })
);

router.get(
    "/:username/achievements",
    validate({ params: z.object({ username: usernameSchema }) }),
    asyncHandler(async (req, res) => {
        const user = await loadProfile(req.valid.params.username);
        if (user.preferences?.publicProfile === false) throw forbidden("That player's profile is private.");
        publicCache(res, 60).json(await achievementsForUser(user._id));
    })
);

router.get(
    "/:username/stats",
    validate({ params: z.object({ username: usernameSchema }) }),
    asyncHandler(async (req, res) => {
        const user = await loadProfile(req.valid.params.username);
        if (user.preferences?.publicProfile === false) throw forbidden("That player's profile is private.");
        publicCache(res, 60).json(await personalStats({ userId: user._id }));
    })
);

export default router;
