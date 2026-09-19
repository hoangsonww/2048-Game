import mongoose from "mongoose";
import bcrypt from "bcryptjs";
import config from "../config/env.js";

const { Schema, model, models } = mongoose;

/**
 * Preferences are stored server-side so a player who signs in on a new device
 * gets their settings, not the defaults. They are content, not behaviour — no
 * preference can change a game rule.
 */
const preferencesSchema = new Schema(
    {
        theme: { type: String, enum: ["system", "light", "dark"], default: "system" },
        reducedMotion: { type: Boolean, default: false },
        soundEnabled: { type: Boolean, default: true },
        hapticsEnabled: { type: Boolean, default: true },
        autoSync: { type: Boolean, default: true },
        publicProfile: { type: Boolean, default: true },
        showOnLeaderboard: { type: Boolean, default: true }
    },
    { _id: false }
);

/**
 * Denormalised career totals.
 *
 * Recomputing a player's lifetime statistics from the score collection on every
 * profile view is the obvious implementation and the wrong one: the read is
 * frequent, the write is rare, and the aggregate is small. These are updated
 * transactionally with each score submission in `scores.service.js`.
 */
const statisticsSchema = new Schema(
    {
        bestScore: { type: Number, default: 0, min: 0 },
        totalScore: { type: Number, default: 0, min: 0 },
        gamesPlayed: { type: Number, default: 0, min: 0 },
        gamesWon: { type: Number, default: 0, min: 0 },
        totalMoves: { type: Number, default: 0, min: 0 },
        highestTile: { type: Number, default: 0, min: 0 },
        totalPlaytimeSeconds: { type: Number, default: 0, min: 0 },
        lastPlayedAt: { type: Date, default: null }
    },
    { _id: false }
);

const userSchema = new Schema(
    {
        username: {
            type: String,
            required: true,
            trim: true,
            minlength: 3,
            maxlength: 24
        },
        // Usernames are case-preserving for display and case-insensitive for
        // identity. Storing the folded form as its own indexed field is what
        // makes "Ada" and "ada" the same account without a collation-dependent
        // unique index that behaves differently between Atlas tiers.
        usernameLower: { type: String, required: true, unique: true, index: true },
        email: { type: String, required: true, unique: true, lowercase: true, trim: true, index: true },
        passwordHash: { type: String, required: true, select: false },
        displayName: { type: String, trim: true, maxlength: 40 },
        country: { type: String, trim: true, uppercase: true, maxlength: 2, default: null },
        avatarColor: { type: String, default: "#e96345", match: /^#[0-9a-fA-F]{6}$/ },
        bio: { type: String, trim: true, maxlength: 280, default: "" },
        roles: { type: [String], default: ["player"], enum: ["player", "moderator", "admin"] },
        preferences: { type: preferencesSchema, default: () => ({}) },
        statistics: { type: statisticsSchema, default: () => ({}) },
        followerCount: { type: Number, default: 0, min: 0 },
        followingCount: { type: Number, default: 0, min: 0 },
        emailVerified: { type: Boolean, default: false },
        disabled: { type: Boolean, default: false },
        lastSeenAt: { type: Date, default: Date.now },
        lastClient: { type: String, default: "unknown" }
    },
    {
        timestamps: true,
        toJSON: { virtuals: true },
        toObject: { virtuals: true }
    }
);

userSchema.index({ "statistics.bestScore": -1, createdAt: 1 });
userSchema.index({ createdAt: -1 });

userSchema.virtual("id").get(function id() {
    return String(this._id);
});

userSchema.pre("validate", function normalizeIdentity(next) {
    if (this.username) this.usernameLower = this.username.toLowerCase();
    if (!this.displayName) this.displayName = this.username;
    next();
});

userSchema.methods.verifyPassword = function verifyPassword(candidate) {
    return bcrypt.compare(candidate, this.passwordHash);
};

userSchema.statics.hashPassword = function hashPassword(plain) {
    return bcrypt.hash(plain, config.auth.bcryptRounds);
};

userSchema.statics.findByIdentifier = function findByIdentifier(identifier) {
    const value = String(identifier).trim().toLowerCase();
    return this.findOne(value.includes("@") ? { email: value } : { usernameLower: value });
};

/** Everything the owner of the account may see. */
userSchema.methods.toPrivateJSON = function toPrivateJSON() {
    return {
        id: String(this._id),
        username: this.username,
        email: this.email,
        displayName: this.displayName,
        country: this.country,
        avatarColor: this.avatarColor,
        bio: this.bio,
        roles: this.roles,
        preferences: this.preferences,
        statistics: this.statistics,
        followerCount: this.followerCount,
        followingCount: this.followingCount,
        emailVerified: this.emailVerified,
        createdAt: this.createdAt,
        updatedAt: this.updatedAt,
        lastSeenAt: this.lastSeenAt
    };
};

/**
 * Everything anyone may see. The email address is absent by construction rather
 * than deleted afterwards, so a new private field cannot leak into a public
 * response by being forgotten.
 */
userSchema.methods.toPublicJSON = function toPublicJSON() {
    return {
        id: String(this._id),
        username: this.username,
        displayName: this.displayName,
        country: this.country,
        avatarColor: this.avatarColor,
        bio: this.preferences?.publicProfile === false ? "" : this.bio,
        statistics: this.preferences?.publicProfile === false
            ? { bestScore: this.statistics?.bestScore ?? 0 }
            : this.statistics,
        followerCount: this.followerCount,
        followingCount: this.followingCount,
        createdAt: this.createdAt
    };
};

export const User = models.User ?? model("User", userSchema);
export default User;
