import express from "express";
import { Follow } from "../models/Follow.js";
import { User } from "../models/User.js";
import { requireAuth } from "../middleware/auth.js";
import { asyncHandler, collection, noStore, requireFeature } from "../lib/http.js";
import { badRequest, notFound } from "../lib/errors.js";
import { paginationSchema, usernameSchema, validate, z } from "../lib/validate.js";

const router = express.Router();
router.use(requireFeature("social"), requireAuth);

async function findTarget(username) {
    const user = await User.findOne({ usernameLower: username.toLowerCase() });
    if (!user || user.disabled) throw notFound("Player");
    return user;
}

router.post(
    "/follow/:username",
    validate({ params: z.object({ username: usernameSchema }) }),
    asyncHandler(async (req, res) => {
        const target = await findTarget(req.valid.params.username);
        if (String(target._id) === String(req.user._id)) throw badRequest("You cannot follow yourself.");

        // Upsert rather than create, so following twice is idempotent instead
        // of a duplicate-key error the client has to special-case.
        const result = await Follow.updateOne(
            { follower: req.user._id, following: target._id },
            { $setOnInsert: { follower: req.user._id, following: target._id } },
            { upsert: true }
        );

        const created = Boolean(result.upsertedCount);
        if (created) {
            await Promise.all([
                User.updateOne({ _id: req.user._id }, { $inc: { followingCount: 1 } }),
                User.updateOne({ _id: target._id }, { $inc: { followerCount: 1 } })
            ]);
        }

        noStore(res).status(created ? 201 : 200).json({ following: true, username: target.username, created });
    })
);

router.delete(
    "/follow/:username",
    validate({ params: z.object({ username: usernameSchema }) }),
    asyncHandler(async (req, res) => {
        const target = await findTarget(req.valid.params.username);
        const result = await Follow.deleteOne({ follower: req.user._id, following: target._id });

        if (result.deletedCount > 0) {
            // Clamped at zero: a counter that can go negative because of a
            // retried delete is worse than one that is briefly stale.
            await Promise.all([
                User.updateOne({ _id: req.user._id, followingCount: { $gt: 0 } }, { $inc: { followingCount: -1 } }),
                User.updateOne({ _id: target._id, followerCount: { $gt: 0 } }, { $inc: { followerCount: -1 } })
            ]);
        }

        noStore(res).json({ following: false, username: target.username, removed: result.deletedCount > 0 });
    })
);

async function listEdges({ res, filter, project, limit, offset }) {
    const [edges, total] = await Promise.all([
        Follow.find(filter).sort({ createdAt: -1 }).skip(offset).limit(limit).populate(project, "username displayName country avatarColor statistics preferences followerCount followingCount createdAt"),
        Follow.countDocuments(filter)
    ]);

    const items = edges
        .map(edge => edge[project])
        .filter(Boolean)
        .map(user => user.toPublicJSON());

    noStore(res).json(collection(items, { total, limit, offset }));
}

router.get(
    "/following",
    validate({ query: paginationSchema }),
    asyncHandler(async (req, res) => {
        const { limit, offset } = req.valid.query;
        await listEdges({ res, filter: { follower: req.user._id }, project: "following", limit, offset });
    })
);

router.get(
    "/followers",
    validate({ query: paginationSchema }),
    asyncHandler(async (req, res) => {
        const { limit, offset } = req.valid.query;
        await listEdges({ res, filter: { following: req.user._id }, project: "follower", limit, offset });
    })
);

router.get(
    "/relationship/:username",
    validate({ params: z.object({ username: usernameSchema }) }),
    asyncHandler(async (req, res) => {
        const target = await findTarget(req.valid.params.username);
        const [following, followsYou] = await Promise.all([
            Follow.exists({ follower: req.user._id, following: target._id }),
            Follow.exists({ follower: target._id, following: req.user._id })
        ]);
        noStore(res).json({ username: target.username, following: Boolean(following), followsYou: Boolean(followsYou) });
    })
);

router.get(
    "/suggestions",
    validate({ query: z.object({ limit: z.coerce.number().int().min(1).max(25).default(10) }) }),
    asyncHandler(async (req, res) => {
        const existing = await Follow.find({ follower: req.user._id }).select("following").lean();
        const exclude = [req.user._id, ...existing.map(edge => edge.following)];

        // "Strong players you are not following yet" is the whole heuristic.
        // A recommendation engine for a leaderboard of a 4x4 puzzle would be
        // machinery in search of a problem.
        const users = await User.find({
            _id: { $nin: exclude },
            disabled: { $ne: true },
            "preferences.publicProfile": { $ne: false },
            "statistics.gamesPlayed": { $gt: 0 }
        })
            .sort({ "statistics.bestScore": -1 })
            .limit(req.valid.query.limit);

        noStore(res).json({ items: users.map(user => user.toPublicJSON()) });
    })
);

export default router;
