import express from "express";
import { GameSave } from "../models/GameSave.js";
import { requireAuth } from "../middleware/auth.js";
import { asyncHandler, noStore, requireFeature } from "../lib/http.js";
import { conflict, notFound } from "../lib/errors.js";
import { boardSchema, clientSchema, slotSchema, validate, z } from "../lib/validate.js";
import { normalizeIncoming, synchronize } from "../services/sync.js";
import config from "../config/env.js";

const router = express.Router();
router.use(requireFeature("cloudSaves"), requireAuth);

const savePayloadSchema = z.object({
    board: boardSchema.optional(),
    grid: boardSchema.optional(),
    score: z.number().int().min(0).default(0),
    bestScore: z.number().int().min(0).optional(),
    best: z.number().int().min(0).optional(),
    won: z.boolean().optional(),
    gameOver: z.boolean().optional(),
    moves: z.number().int().min(0).default(0),
    elapsedSeconds: z.number().int().min(0).default(0),
    label: z.string().trim().max(60).optional(),
    deviceId: z.string().trim().max(64).optional(),
    client: clientSchema,
    // The revision this device last saw. Present, it proves the local round
    // descends from the stored one and the write is a continuation rather than
    // a divergence; absent, every difference is treated as a conflict.
    baseRevision: z.number().int().min(0).optional(),
    undo: z
        .object({
            board: boardSchema,
            score: z.number().int().min(0).default(0),
            won: z.boolean().default(false)
        })
        .nullable()
        .optional()
}).refine(value => value.board ?? value.grid, { message: "Provide either `board` (16 cells) or `grid` (4x4)." });

router.get(
    "/",
    asyncHandler(async (req, res) => {
        const saves = await GameSave.find({ user: req.user._id }).sort({ updatedAt: -1 });
        noStore(res).json({
            items: saves.map(save => save.toJSON()),
            limits: { maxSlots: config.limits.maxSaveSlots }
        });
    })
);

router.get(
    "/current",
    asyncHandler(async (req, res) => {
        const save = await GameSave.findOne({ user: req.user._id, slot: "current" });
        if (!save) throw notFound("Cloud save");
        noStore(res).json({ save: save.toJSON() });
    })
);

/**
 * Two-way sync. This is the endpoint a client should call on launch, on sign
 * in, and when it comes back online — it is the only one that can resolve a
 * disagreement between devices without losing a round.
 */
router.post(
    "/sync",
    validate({
        body: z.object({
            slot: slotSchema.default("current"),
            strategy: z.enum(["auto", "prefer-local", "prefer-remote"]).default("auto"),
            save: savePayloadSchema.nullable().optional()
        })
    }),
    asyncHandler(async (req, res) => {
        const { slot, strategy, save } = req.valid.body;
        const result = await synchronize({
            userId: req.user._id,
            slot,
            localSave: save ?? null,
            strategy
        });

        req.log?.info("saves.sync", { userId: String(req.user._id), slot, resolution: result.resolution });

        noStore(res).json({
            resolution: result.resolution,
            winner: result.winner ?? null,
            conflictSlot: result.conflictSlot,
            save: result.save ? result.save.toJSON() : null
        });
    })
);

router.put(
    "/current",
    validate({ body: savePayloadSchema }),
    asyncHandler(async (req, res) => {
        const result = await synchronize({
            userId: req.user._id,
            slot: "current",
            localSave: req.valid.body,
            strategy: "prefer-local"
        });
        noStore(res).json({ save: result.save.toJSON(), resolution: result.resolution });
    })
);

router.get(
    "/:slot",
    validate({ params: z.object({ slot: slotSchema }) }),
    asyncHandler(async (req, res) => {
        const save = await GameSave.findOne({ user: req.user._id, slot: req.valid.params.slot });
        if (!save) throw notFound("Save slot");
        noStore(res).json({ save: save.toJSON() });
    })
);

router.put(
    "/:slot",
    validate({ params: z.object({ slot: slotSchema }), body: savePayloadSchema }),
    asyncHandler(async (req, res) => {
        const { slot } = req.valid.params;
        const existing = await GameSave.findOne({ user: req.user._id, slot });

        if (!existing) {
            const count = await GameSave.countDocuments({ user: req.user._id });
            if (count >= config.limits.maxSaveSlots) {
                throw conflict(`You already have ${config.limits.maxSaveSlots} save slots. Delete one before creating another.`, {
                    maxSlots: config.limits.maxSaveSlots
                });
            }
        }

        const incoming = normalizeIncoming(req.valid.body);
        const save = await GameSave.findOneAndUpdate(
            { user: req.user._id, slot },
            { $set: { ...incoming, revision: (existing?.revision ?? 0) + 1 }, $setOnInsert: { user: req.user._id, slot } },
            { upsert: true, new: true, setDefaultsOnInsert: true, runValidators: true }
        );

        noStore(res).status(existing ? 200 : 201).json({ save: save.toJSON() });
    })
);

router.delete(
    "/:slot",
    validate({ params: z.object({ slot: slotSchema }) }),
    asyncHandler(async (req, res) => {
        const result = await GameSave.deleteOne({ user: req.user._id, slot: req.valid.params.slot });
        if (result.deletedCount === 0) throw notFound("Save slot");
        noStore(res).json({ deleted: true, slot: req.valid.params.slot });
    })
);

router.delete(
    "/",
    validate({ body: z.object({ confirm: z.literal("DELETE") }) }),
    asyncHandler(async (req, res) => {
        const result = await GameSave.deleteMany({ user: req.user._id });
        noStore(res).json({ deleted: true, count: result.deletedCount ?? 0 });
    })
);

export default router;
