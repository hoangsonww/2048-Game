import mongoose from "mongoose";

const { Schema, model, models } = mongoose;

/**
 * Coarse gameplay telemetry, opt-in and pseudonymous.
 *
 * This exists to answer product questions the leaderboard cannot ("do players
 * who use undo reach 2048 more often?"), so it records *event kinds*, never
 * content. There is no device fingerprint, no IP, and no third-party sink —
 * see docs/privacy.md. Documents expire after 90 days via a TTL index, because
 * telemetry that is never deleted is a liability rather than a dataset.
 */
const gameEventSchema = new Schema(
    {
        user: { type: Schema.Types.ObjectId, ref: "User", default: null, index: true },
        anonymousId: { type: String, default: "", maxlength: 64 },
        type: {
            type: String,
            required: true,
            enum: [
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
            ],
            index: true
        },
        client: { type: String, default: "unknown", index: true },
        value: { type: Number, default: 0 },
        metadata: { type: Schema.Types.Mixed, default: {} },
        occurredAt: { type: Date, default: Date.now, index: true },
        expiresAt: {
            type: Date,
            default: () => new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)
        }
    },
    { timestamps: true }
);

gameEventSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
gameEventSchema.index({ type: 1, occurredAt: -1 });

export const GameEvent = models.GameEvent ?? model("GameEvent", gameEventSchema);
export default GameEvent;
