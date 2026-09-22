import express from "express";
import { requireAuth } from "../middleware/auth.js";
import { asyncHandler, noStore, publicCache } from "../lib/http.js";
import { notFound } from "../lib/errors.js";
import { validate, z } from "../lib/validate.js";
import { achievementCatalog, achievementsForUser, findAchievement } from "../services/achievements.js";

const router = express.Router();

router.get(
    "/",
    asyncHandler(async (_req, res) => {
        // The catalog is compiled into the build, so it changes only on deploy
        // and can be cached hard.
        publicCache(res, 3600).json({ items: achievementCatalog() });
    })
);

router.get(
    "/me",
    requireAuth,
    asyncHandler(async (req, res) => {
        noStore(res).json(await achievementsForUser(req.user._id));
    })
);

router.get(
    "/:key",
    validate({ params: z.object({ key: z.string().trim().min(1).max(64) }) }),
    asyncHandler(async (req, res) => {
        const definition = findAchievement(req.valid.params.key);
        if (!definition) throw notFound("Achievement");
        const { key, name, description, category, points } = definition;
        publicCache(res, 3600).json({ achievement: { key, name, description, category, points } });
    })
);

export default router;
