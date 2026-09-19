import mongoose from "mongoose";

const { Schema, model, models } = mongoose;

/**
 * One row per signed-in device.
 *
 * Only the SHA-256 of the refresh token is stored, so the collection is not a
 * credential store. `expiresAt` carries a TTL index, which means expired
 * sessions are reaped by Mongo rather than by a cron job this deployment does
 * not have.
 */
const sessionSchema = new Schema(
    {
        user: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
        sessionId: { type: String, required: true, unique: true, index: true },
        refreshTokenHash: { type: String, required: true, index: true },
        client: { type: String, default: "unknown" },
        userAgent: { type: String, default: "", maxlength: 400 },
        ip: { type: String, default: "" },
        lastUsedAt: { type: Date, default: Date.now },
        revokedAt: { type: Date, default: null },
        expiresAt: { type: Date, required: true }
    },
    { timestamps: true }
);

sessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
sessionSchema.index({ user: 1, revokedAt: 1, lastUsedAt: -1 });

sessionSchema.methods.isActive = function isActive() {
    return !this.revokedAt && this.expiresAt.getTime() > Date.now();
};

sessionSchema.methods.toJSON = function toJSON() {
    return {
        id: this.sessionId,
        client: this.client,
        userAgent: this.userAgent,
        createdAt: this.createdAt,
        lastUsedAt: this.lastUsedAt,
        expiresAt: this.expiresAt,
        revoked: Boolean(this.revokedAt)
    };
};

export const Session = models.Session ?? model("Session", sessionSchema);
export default Session;
