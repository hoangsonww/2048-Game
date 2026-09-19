import express from "express";
import { User } from "../models/User.js";
import { Session } from "../models/Session.js";
import { GameSave } from "../models/GameSave.js";
import { Score } from "../models/Score.js";
import { UserAchievement } from "../models/UserAchievement.js";
import { Follow } from "../models/Follow.js";
import { GameEvent } from "../models/GameEvent.js";
import { asyncHandler, noStore } from "../lib/http.js";
import { conflict, forbidden, invalidCredentials, notFound, unauthorized } from "../lib/errors.js";
import { hashToken, issueTokenPair, newSessionId, verifyRefreshToken } from "../lib/tokens.js";
import { clientSchema, displayNameSchema, emailSchema, passwordSchema, usernameSchema, validate, z } from "../lib/validate.js";
import { requireAuth } from "../middleware/auth.js";
import config from "../config/env.js";

const router = express.Router();

function sessionExpiry() {
    return new Date(Date.now() + config.auth.refreshTtlSeconds * 1000);
}

/**
 * Sessions are created here and only here. Capping them keeps a player who
 * signs in from a new browser every day from accumulating an unbounded list of
 * live refresh tokens; the oldest is revoked rather than deleted so the list
 * still explains what happened.
 */
async function createSession(user, req, client) {
    const sessionId = newSessionId();
    const tokens = issueTokenPair(user, sessionId);

    await Session.create({
        user: user._id,
        sessionId,
        refreshTokenHash: hashToken(tokens.refreshToken),
        client,
        userAgent: (req.get("user-agent") ?? "").slice(0, 400),
        ip: req.ip ?? "",
        expiresAt: sessionExpiry()
    });

    const active = await Session.find({ user: user._id, revokedAt: null }).sort({ lastUsedAt: -1 }).select("_id").lean();
    if (active.length > config.auth.maxSessionsPerUser) {
        const excess = active.slice(config.auth.maxSessionsPerUser).map(entry => entry._id);
        await Session.updateMany({ _id: { $in: excess } }, { $set: { revokedAt: new Date() } });
    }

    return tokens;
}

const registerSchema = z.object({
    username: usernameSchema,
    email: emailSchema,
    password: passwordSchema,
    displayName: displayNameSchema.optional(),
    country: z.string().trim().length(2).toUpperCase().optional(),
    client: clientSchema
});

router.post(
    "/register",
    validate({ body: registerSchema }),
    asyncHandler(async (req, res) => {
        if (!config.features.registrationOpen) throw forbidden("Registration is currently closed.");
        const { username, email, password, displayName, country, client } = req.valid.body;

        // Checked explicitly so the client can highlight the offending field.
        // The unique indexes remain the real guarantee — this is a better error
        // message, not the enforcement.
        const [usernameTaken, emailTaken] = await Promise.all([
            User.exists({ usernameLower: username.toLowerCase() }),
            User.exists({ email })
        ]);
        if (usernameTaken) throw conflict("That username is already taken.", { field: "username" });
        if (emailTaken) throw conflict("An account already uses that email address.", { field: "email" });

        const user = await User.create({
            username,
            email,
            passwordHash: await User.hashPassword(password),
            displayName: displayName ?? username,
            country: country ?? null,
            lastClient: client
        });

        const tokens = await createSession(user, req, client);
        req.log?.info("auth.registered", { userId: String(user._id), client });

        noStore(res).status(201).json({ user: user.toPrivateJSON(), ...tokens });
    })
);

const loginSchema = z.object({
    // Either a username or an email address; players remember one or the other.
    identifier: z.string().trim().min(3).max(254),
    password: z.string().min(1).max(200),
    client: clientSchema
});

router.post(
    "/login",
    validate({ body: loginSchema }),
    asyncHandler(async (req, res) => {
        const { identifier, password, client } = req.valid.body;

        const user = await User.findByIdentifier(identifier).select("+passwordHash");
        // The same error for an unknown account and a wrong password, so the
        // endpoint cannot be used to enumerate who has an account here.
        if (!user) throw invalidCredentials();
        if (user.disabled) throw forbidden("This account has been disabled.");
        if (!(await user.verifyPassword(password))) throw invalidCredentials();

        user.lastSeenAt = new Date();
        user.lastClient = client;
        await user.save();

        const tokens = await createSession(user, req, client);
        req.log?.info("auth.signed_in", { userId: String(user._id), client });

        noStore(res).json({ user: user.toPrivateJSON(), ...tokens });
    })
);

router.post(
    "/refresh",
    validate({ body: z.object({ refreshToken: z.string().min(10) }) }),
    asyncHandler(async (req, res) => {
        const { refreshToken } = req.valid.body;
        const payload = verifyRefreshToken(refreshToken);

        const session = await Session.findOne({ sessionId: payload.sid });
        if (!session || !session.isActive()) throw unauthorized("That session is no longer active.");
        if (session.refreshTokenHash !== hashToken(refreshToken)) {
            // The token verified but does not match the stored hash, which
            // means an older token from a rotated session was replayed. The
            // safe response is to kill the session rather than to refresh it.
            session.revokedAt = new Date();
            await session.save();
            req.log?.warn("auth.refresh_reuse", { sessionId: session.sessionId });
            throw unauthorized("That refresh token has already been rotated.");
        }

        const user = await User.findById(payload.sub);
        if (!user) throw unauthorized("The account for this token no longer exists.");
        if (user.disabled) throw forbidden("This account has been disabled.");

        // Rotation: every refresh issues a new pair and invalidates the old one.
        const tokens = issueTokenPair(user, session.sessionId);
        session.refreshTokenHash = hashToken(tokens.refreshToken);
        session.lastUsedAt = new Date();
        session.expiresAt = sessionExpiry();
        await session.save();

        noStore(res).json({ user: user.toPrivateJSON(), ...tokens });
    })
);

router.post(
    "/logout",
    validate({ body: z.object({ refreshToken: z.string().min(10).optional() }).default({}) }),
    asyncHandler(async (req, res) => {
        const { refreshToken } = req.valid.body ?? {};
        if (refreshToken) {
            const hash = hashToken(refreshToken);
            await Session.updateOne({ refreshTokenHash: hash, revokedAt: null }, { $set: { revokedAt: new Date() } });
        }
        noStore(res).json({ signedOut: true });
    })
);

router.post(
    "/logout-all",
    requireAuth,
    asyncHandler(async (req, res) => {
        const result = await Session.updateMany({ user: req.user._id, revokedAt: null }, { $set: { revokedAt: new Date() } });
        noStore(res).json({ signedOut: true, sessionsRevoked: result.modifiedCount ?? 0 });
    })
);

router.get(
    "/me",
    requireAuth,
    asyncHandler(async (req, res) => {
        noStore(res).json({ user: req.user.toPrivateJSON() });
    })
);

router.patch(
    "/me",
    requireAuth,
    validate({
            body: z
                .object({
                    displayName: displayNameSchema.optional(),
                    country: z.string().trim().length(2).toUpperCase().nullable().optional(),
                    avatarColor: z.string().regex(/^#[0-9a-fA-F]{6}$/).optional(),
                    bio: z.string().trim().max(280).optional()
                })
                .strict()
    }),
    asyncHandler(async (req, res) => {
        Object.assign(req.user, req.valid.body);
        await req.user.save();
        noStore(res).json({ user: req.user.toPrivateJSON() });
    })
);

router.post(
    "/change-password",
    requireAuth,
    validate({
        body: z.object({
            currentPassword: z.string().min(1).max(200),
            newPassword: passwordSchema,
            signOutOtherSessions: z.boolean().default(true)
        })
    }),
    asyncHandler(async (req, res) => {
        const { currentPassword, newPassword, signOutOtherSessions } = req.valid.body;
        const user = await User.findById(req.user._id).select("+passwordHash");
        if (!(await user.verifyPassword(currentPassword))) throw invalidCredentials();

        user.passwordHash = await User.hashPassword(newPassword);
        await user.save();

        let revoked = 0;
        if (signOutOtherSessions) {
            // A password change that leaves other devices signed in is not a
            // password change, so every session except the current one goes.
            const result = await Session.updateMany(
                { user: user._id, revokedAt: null, sessionId: { $ne: req.auth.sessionId } },
                { $set: { revokedAt: new Date() } }
            );
            revoked = result.modifiedCount ?? 0;
        }

        noStore(res).json({ changed: true, sessionsRevoked: revoked });
    })
);

router.get(
    "/sessions",
    requireAuth,
    asyncHandler(async (req, res) => {
        const sessions = await Session.find({ user: req.user._id }).sort({ lastUsedAt: -1 }).limit(50);
        noStore(res).json({
            items: sessions.map(session => ({ ...session.toJSON(), current: session.sessionId === req.auth.sessionId }))
        });
    })
);

router.delete(
    "/sessions/:sessionId",
    requireAuth,
    validate({ params: z.object({ sessionId: z.string().uuid() }) }),
    asyncHandler(async (req, res) => {
        const session = await Session.findOne({ user: req.user._id, sessionId: req.valid.params.sessionId });
        if (!session) throw notFound("Session");
        session.revokedAt = new Date();
        await session.save();
        noStore(res).json({ revoked: true, id: session.sessionId });
    })
);

router.delete(
    "/me",
    requireAuth,
    validate({ body: z.object({ password: z.string().min(1).max(200), confirm: z.literal("DELETE") }) }),
    asyncHandler(async (req, res) => {
        const user = await User.findById(req.user._id).select("+passwordHash");
        if (!(await user.verifyPassword(req.valid.body.password))) throw invalidCredentials();

        // Deletion means deletion. Every collection that references the account
        // is cleared in the same request; there is no soft-delete tombstone
        // holding the player's rounds after they asked for them to be gone.
        // See docs/privacy.md.
        const userId = user._id;
        await Promise.all([
            Session.deleteMany({ user: userId }),
            GameSave.deleteMany({ user: userId }),
            Score.deleteMany({ user: userId }),
            UserAchievement.deleteMany({ user: userId }),
            Follow.deleteMany({ $or: [{ follower: userId }, { following: userId }] }),
            GameEvent.deleteMany({ user: userId })
        ]);
        await User.deleteOne({ _id: userId });

        req.log?.info("auth.account_deleted", { userId: String(userId) });
        noStore(res).json({ deleted: true });
    })
);

router.get(
    "/available",
    validate({
        query: z.object({
            username: usernameSchema.optional(),
            email: emailSchema.optional()
        })
    }),
    asyncHandler(async (req, res) => {
        const { username, email } = req.valid.query;
        const response = {};
        if (username) response.username = { value: username, available: !(await User.exists({ usernameLower: username.toLowerCase() })) };
        if (email) response.email = { value: email, available: !(await User.exists({ email })) };
        noStore(res).json(response);
    })
);

export default router;
