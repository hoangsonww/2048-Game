import mongoose from "mongoose";

const { Schema, model, models } = mongoose;

/**
 * One finished (or abandoned) round.
 *
 * Scores are append-only history; the leaderboard is an aggregation over this
 * collection, never a separately maintained table that can drift from it.
 *
 * `signature` is a board fingerprint plus score, unique per user. A client that
 * retries a submission after a flaky network gets the original row back rather
 * than a duplicate leaderboard entry — the submission is idempotent without the
 * client having to invent an identifier.
 */
const scoreSchema = new Schema(
    {
        user: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
        username: { type: String, required: true, index: true },
        displayName: { type: String, default: "" },
        country: { type: String, default: null },
        avatarColor: { type: String, default: "#e96345" },
        score: { type: Number, required: true, min: 0, index: true },
        highestTile: { type: Number, required: true, min: 0, index: true },
        moves: { type: Number, default: 0, min: 0 },
        durationSeconds: { type: Number, default: 0, min: 0 },
        won: { type: Boolean, default: false, index: true },
        gameOver: { type: Boolean, default: false },
        board: { type: [Number], default: [] },
        mode: { type: String, enum: ["classic", "daily"], default: "classic", index: true },
        challengeDate: { type: String, default: null, index: true },
        client: { type: String, default: "unknown" },
        signature: { type: String, required: true },
        // Recorded but never trusted: a score whose ceiling check failed is kept
        // out of the leaderboard rather than rejected outright, so a genuine
        // client bug shows up as data instead of as a lost round.
        verified: { type: Boolean, default: true, index: true },
        verificationNote: { type: String, default: "" }
    },
    { timestamps: true }
);

scoreSchema.index({ user: 1, signature: 1 }, { unique: true });
scoreSchema.index({ verified: 1, mode: 1, score: -1, createdAt: 1 });
scoreSchema.index({ mode: 1, challengeDate: 1, score: -1 });
scoreSchema.index({ user: 1, createdAt: -1 });
scoreSchema.index({ createdAt: -1 });

scoreSchema.methods.toJSON = function toJSON() {
    return {
        id: String(this._id),
        username: this.username,
        displayName: this.displayName,
        country: this.country,
        avatarColor: this.avatarColor,
        score: this.score,
        highestTile: this.highestTile,
        moves: this.moves,
        durationSeconds: this.durationSeconds,
        won: this.won,
        gameOver: this.gameOver,
        mode: this.mode,
        challengeDate: this.challengeDate,
        client: this.client,
        verified: this.verified,
        createdAt: this.createdAt
    };
};

export const Score = models.Score ?? model("Score", scoreSchema);
export default Score;
