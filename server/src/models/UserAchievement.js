import mongoose from "mongoose";

const { Schema, model, models } = mongoose;

/**
 * An unlocked achievement.
 *
 * The catalog itself lives in code (`services/achievements.js`) rather than in
 * the database: definitions are behaviour, and behaviour belongs in a build
 * that can be reviewed and tested, not in a document anyone can edit. Only the
 * *unlock* is data.
 */
const userAchievementSchema = new Schema(
    {
        user: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
        key: { type: String, required: true, index: true },
        progress: { type: Number, default: 0, min: 0 },
        target: { type: Number, default: 1, min: 1 },
        unlockedAt: { type: Date, default: null },
        context: { type: Schema.Types.Mixed, default: {} }
    },
    { timestamps: true }
);

userAchievementSchema.index({ user: 1, key: 1 }, { unique: true });
userAchievementSchema.index({ user: 1, unlockedAt: -1 });

userAchievementSchema.methods.toJSON = function toJSON() {
    return {
        key: this.key,
        progress: this.progress,
        target: this.target,
        unlocked: Boolean(this.unlockedAt),
        unlockedAt: this.unlockedAt,
        updatedAt: this.updatedAt
    };
};

export const UserAchievement = models.UserAchievement ?? model("UserAchievement", userAchievementSchema);
export default UserAchievement;
