/**
 * Authentication and authorisation.
 *
 * `requireAuth` loads the user document, because almost every authenticated
 * route needs it and a second round trip per request is not worth saving a
 * lookup the driver will serve from a warm connection. `optionalAuth` is for
 * routes whose response is richer when signed in but valid when not — the
 * leaderboard marking your own row, for instance.
 */
import { User } from "../models/User.js";
import { bearerToken, verifyAccessToken } from "../lib/tokens.js";
import { forbidden, unauthorized } from "../lib/errors.js";
import { connectToDatabase } from "../config/database.js";

async function resolveUser(req) {
    const token = bearerToken(req.get("authorization"));
    if (!token) return null;

    const payload = verifyAccessToken(token);
    await connectToDatabase();
    const user = await User.findById(payload.sub);
    if (!user) throw unauthorized("The account for this token no longer exists.");
    if (user.disabled) throw forbidden("This account has been disabled.");

    req.auth = { userId: String(user._id), sessionId: payload.sid, roles: payload.roles ?? user.roles };
    req.user = user;
    return user;
}

export async function requireAuth(req, _res, next) {
    try {
        const user = await resolveUser(req);
        if (!user) throw unauthorized("Provide an access token as `Authorization: Bearer <token>`.");
        next();
    } catch (error) {
        next(error);
    }
}

export async function optionalAuth(req, _res, next) {
    try {
        await resolveUser(req);
        next();
    } catch (error) {
        // A malformed or expired token on an optional route degrades to
        // anonymous rather than failing the request. The alternative punishes a
        // signed-out reader for a stale token their browser still remembers.
        if (error?.status === 401) {
            req.auth = null;
            req.user = null;
            next();
            return;
        }
        next(error);
    }
}

export function requireRole(...roles) {
    return (req, _res, next) => {
        const granted = req.user?.roles ?? [];
        next(roles.some(role => granted.includes(role)) ? undefined : forbidden("This endpoint requires elevated access."));
    };
}

export default { requireAuth, optionalAuth, requireRole };
