import express from "express";
import { requireAuth } from "../middleware/auth.js";
import { asyncHandler, noStore, publicCache } from "../lib/http.js";
import { validate, z } from "../lib/validate.js";
import { activitySeries, globalStats, personalStats, tileDistribution } from "../services/stats.js";

const router = express.Router();

router.get(
    "/global",
    asyncHandler(async (_req, res) => {
        publicCache(res, 60).json(await globalStats());
    })
);

router.get(
    "/tiles",
    asyncHandler(async (_req, res) => {
        publicCache(res, 120).json(await tileDistribution());
    })
);

router.get(
    "/activity",
    validate({ query: z.object({ days: z.coerce.number().int().min(1).max(365).default(30) }) }),
    asyncHandler(async (req, res) => {
        publicCache(res, 120).json(await activitySeries({ days: req.valid.query.days }));
    })
);

router.get(
    "/me",
    requireAuth,
    asyncHandler(async (req, res) => {
        noStore(res).json(await personalStats({ userId: req.user._id }));
    })
);

router.get(
    "/me/activity",
    requireAuth,
    validate({ query: z.object({ days: z.coerce.number().int().min(1).max(365).default(30) }) }),
    asyncHandler(async (req, res) => {
        noStore(res).json(await activitySeries({ userId: req.user._id, days: req.valid.query.days }));
    })
);

export default router;
