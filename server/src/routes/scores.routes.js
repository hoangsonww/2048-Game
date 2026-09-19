import express from "express";
import { Score } from "../models/Score.js";
import { requireAuth } from "../middleware/auth.js";
import { asyncHandler, collection, noStore } from "../lib/http.js";
import { notFound } from "../lib/errors.js";
import { boardSchema, clientSchema, objectIdSchema, paginationSchema, scoreValueSchema, validate, z } from "../lib/validate.js";
import { submitScore } from "../services/scores.js";
import { personalStats } from "../services/stats.js";

const router = express.Router();
router.use(requireAuth);

router.post(
    "/",
    validate({
        body: z.object({
            board: boardSchema.optional(),
            grid: boardSchema.optional(),
            score: scoreValueSchema,
            moves: z.number().int().min(0).max(1_000_000).default(0),
            durationSeconds: z.number().int().min(0).max(86_400 * 7).default(0),
            mode: z.enum(["classic", "daily"]).default("classic"),
            challengeDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
            client: clientSchema
        }).refine(value => value.board ?? value.grid, { message: "Provide either `board` (16 cells) or `grid` (4x4)." })
    }),
    asyncHandler(async (req, res) => {
        const body = req.valid.body;
        const result = await submitScore({
            user: req.user,
            board: body.board ?? body.grid,
            score: body.score,
            moves: body.moves,
            durationSeconds: body.durationSeconds,
            mode: body.mode,
            challengeDate: body.challengeDate ?? null,
            client: body.client
        });

        req.log?.info("scores.submitted", {
            userId: String(req.user._id),
            score: body.score,
            duplicate: result.duplicate,
            verified: result.score.verified
        });

        // A duplicate is a success, not a failure: the client retried and the
        // original row is authoritative. 200 rather than 201 tells it so.
        noStore(res).status(result.duplicate ? 200 : 201).json({
            score: result.score.toJSON(),
            duplicate: result.duplicate,
            unlockedAchievements: result.unlockedAchievements,
            statistics: result.statistics
        });
    })
);

router.get(
    "/",
    validate({
        query: paginationSchema.extend({
            mode: z.enum(["classic", "daily", "all"]).default("all"),
            sort: z.enum(["recent", "score"]).default("recent"),
            wonOnly: z.coerce.boolean().default(false)
        })
    }),
    asyncHandler(async (req, res) => {
        const { limit, offset, mode, sort, wonOnly } = req.valid.query;
        const filter = { user: req.user._id };
        if (mode !== "all") filter.mode = mode;
        if (wonOnly) filter.won = true;

        const [items, total] = await Promise.all([
            Score.find(filter)
                .sort(sort === "score" ? { score: -1, createdAt: 1 } : { createdAt: -1 })
                .skip(offset)
                .limit(limit),
            Score.countDocuments(filter)
        ]);

        noStore(res).json(collection(items.map(item => item.toJSON()), { total, limit, offset }));
    })
);

router.get(
    "/best",
    asyncHandler(async (req, res) => {
        const best = await Score.findOne({ user: req.user._id, verified: true }).sort({ score: -1, createdAt: 1 });
        noStore(res).json({ best: best ? best.toJSON() : null });
    })
);

router.get(
    "/stats",
    asyncHandler(async (req, res) => {
        noStore(res).json(await personalStats({ userId: req.user._id }));
    })
);

router.get(
    "/:id",
    validate({ params: z.object({ id: objectIdSchema }) }),
    asyncHandler(async (req, res) => {
        const score = await Score.findOne({ _id: req.valid.params.id, user: req.user._id });
        if (!score) throw notFound("Score");
        noStore(res).json({ score: { ...score.toJSON(), board: score.board } });
    })
);

router.delete(
    "/:id",
    validate({ params: z.object({ id: objectIdSchema }) }),
    asyncHandler(async (req, res) => {
        const result = await Score.deleteOne({ _id: req.valid.params.id, user: req.user._id });
        if (result.deletedCount === 0) throw notFound("Score");
        // Career totals are intentionally left alone. They are a lifetime
        // record of rounds played, and rewriting history because a row was
        // removed would make "games played" go down, which no player expects.
        noStore(res).json({ deleted: true });
    })
);

export default router;
