/**
 * Access and refresh tokens.
 *
 * Access tokens are short-lived, stateless JWTs — a request never reads the
 * database to authenticate. Refresh tokens are long-lived and *stateful*: only
 * a SHA-256 hash of the token is stored, so a leaked database dump cannot be
 * replayed as a login, and revoking a session is a single document update.
 */
import crypto from "node:crypto";
import jwt from "jsonwebtoken";
import config from "../config/env.js";
import { unauthorized } from "./errors.js";

export function signAccessToken(user, sessionId) {
    return jwt.sign(
        {
            sub: String(user._id),
            username: user.username,
            roles: user.roles ?? ["player"],
            sid: sessionId,
            typ: "access"
        },
        config.auth.accessSecret,
        {
            expiresIn: config.auth.accessTtlSeconds,
            issuer: config.auth.issuer,
            audience: config.auth.audience
        }
    );
}

export function signRefreshToken(user, sessionId) {
    return jwt.sign(
        {
            sub: String(user._id),
            sid: sessionId,
            typ: "refresh",
            // Without a unique claim, two refreshes inside the same second
            // produce byte-identical tokens — `iat` and `exp` have one-second
            // resolution and nothing else in the payload changes. Rotation
            // would then silently not rotate, and replay detection, which
            // compares digests, would never fire.
            jti: crypto.randomUUID()
        },
        config.auth.refreshSecret,
        {
            expiresIn: config.auth.refreshTtlSeconds,
            issuer: config.auth.issuer,
            audience: config.auth.audience
        }
    );
}

function verify(token, secret, expectedType) {
    try {
        const payload = jwt.verify(token, secret, {
            issuer: config.auth.issuer,
            audience: config.auth.audience
        });
        if (payload.typ !== expectedType) {
            throw unauthorized(`Expected a ${expectedType} token.`);
        }
        return payload;
    } catch (error) {
        if (error.name === "TokenExpiredError") {
            throw unauthorized(`Your ${expectedType} token has expired.`);
        }
        if (error.status) throw error;
        throw unauthorized(`That ${expectedType} token is not valid.`);
    }
}

export const verifyAccessToken = token => verify(token, config.auth.accessSecret, "access");
export const verifyRefreshToken = token => verify(token, config.auth.refreshSecret, "refresh");

/** Refresh tokens are stored hashed; comparison is over the digest, never the token. */
export function hashToken(token) {
    return crypto.createHash("sha256").update(token).digest("hex");
}

export function newSessionId() {
    return crypto.randomUUID();
}

export function issueTokenPair(user, sessionId = newSessionId()) {
    return {
        sessionId,
        accessToken: signAccessToken(user, sessionId),
        refreshToken: signRefreshToken(user, sessionId),
        tokenType: "Bearer",
        expiresIn: config.auth.accessTtlSeconds,
        refreshExpiresIn: config.auth.refreshTtlSeconds
    };
}

/** Reads a bearer token out of an Authorization header, or returns null. */
export function bearerToken(header) {
    if (typeof header !== "string") return null;
    const [scheme, value] = header.split(" ");
    if (!value || scheme.toLowerCase() !== "bearer") return null;
    return value.trim() || null;
}

export default {
    signAccessToken,
    signRefreshToken,
    verifyAccessToken,
    verifyRefreshToken,
    hashToken,
    newSessionId,
    issueTokenPair,
    bearerToken
};
