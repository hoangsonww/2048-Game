import express from "express";
import { GameEvent } from "../models/GameEvent.js";
import { optionalAuth } from "../middleware/auth.js";
import { asyncHandler, noStore, requireFeature } from "../lib/http.js";
import { clientSchema, validate, z } from "../lib/validate.js";
import config from "../config/env.js";

const router = express.Router();
router.use(requireFeature("events"));

const eventSchema = z.object({
    type: z.enum([
        "game_started",
        "game_over",
        "game_won",
        "move",
        "undo",
        "milestone_tile",
        "sync_completed",
        "sync_conflict",
        "account_created",
        "signed_in"
    ]),
    value: z.number().int().min(0).max(10_000_000).default(0),
    occurredAt: z.coerce.date().optional(),
    // A closed key set, so a client cannot turn telemetry into a general
    // key-value sink or accidentally post the contents of a board.
    metadata: z
        .object({
            direction: z.enum(["up", "down", "left", "right"]).optional(),
            highestTile: z.number().int().min(0).max(131_072).optional(),
            moves: z.number().int().min(0).max(1_000_000).optional(),
            resolution: z.enum(["uploaded", "downloaded", "in_sync", "conflicted"]).optional()
        })
        .strict()
        .default({})
});

router.post(
    "/",
    optionalAuth,
    validate({
        body: z.object({
            client: clientSchema,
            anonymousId: z.string().trim().max(64).optional(),
            events: z.array(eventSchema).min(1).max(config.limits.maxEventsPerBatch)
        })
    }),
    asyncHandler(async (req, res) => {
        const { client, anonymousId, events } = req.valid.body;

        await GameEvent.insertMany(
            events.map(event => ({
                user: req.user?._id ?? null,
                // A signed-in player's events are keyed by account, so the
                // anonymous identifier is dropped rather than stored alongside
                // it — keeping both would link the two forever.
                anonymousId: req.user ? "" : (anonymousId ?? "").slice(0, 64),
                type: event.type,
                client,
                value: event.value,
                metadata: event.metadata,
                occurredAt: event.occurredAt ?? new Date()
            })),
            { ordered: false }
        );

        noStore(res).status(202).json({ accepted: events.length });
    })
);

router.get(
    "/summary",
    validate({ query: z.object({ days: z.coerce.number().int().min(1).max(90).default(7) }) }),
    asyncHandler(async (req, res) => {
        const since = new Date(Date.now() - req.valid.query.days * 86_400_000);
        const rows = await GameEvent.aggregate([
            { $match: { occurredAt: { $gte: since } } },
            { $group: { _id: { type: "$type", client: "$client" }, count: { $sum: 1 } } },
            { $sort: { count: -1 } }
        ]);

        noStore(res).json({
            days: req.valid.query.days,
            since,
            items: rows.map(row => ({ type: row._id.type, client: row._id.client, count: row.count }))
        });
    })
);

export default router;
