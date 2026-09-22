import mongoose from "mongoose";

const { Schema, model, models } = mongoose;

/**
 * A directed follow edge, used only to scope a leaderboard to people you care
 * about. There is no feed, no messaging, and no notification surface — the
 * social model is deliberately the smallest thing that makes a friends
 * leaderboard possible.
 */
const followSchema = new Schema(
    {
        follower: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
        following: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true }
    },
    { timestamps: true }
);

followSchema.index({ follower: 1, following: 1 }, { unique: true });
followSchema.index({ following: 1, createdAt: -1 });

export const Follow = models.Follow ?? model("Follow", followSchema);
export default Follow;
