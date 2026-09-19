/**
 * Rate limiting.
 *
 * The store is in-memory, which on Vercel means per-instance rather than
 * global. That is honest protection against a single misbehaving client and a
 * runaway loop in a client build; it is not a defence against a distributed
 * attack, and is documented as such in docs/backend.md. A Redis-backed store is
 * a one-line change to this file if that ever becomes necessary.
 */
import rateLimit from "express-rate-limit";
import config from "../config/env.js";
import { tooManyRequests } from "../lib/errors.js";

/**
 * IPv6 addresses are allocated to a subscriber a /64 at a time, so limiting a
 * single address limits nothing: the same client can present a different one
 * on every request. Truncating to the /64 makes the bucket match the
 * allocation. IPv4 addresses are used whole.
 */
function addressKey(ip) {
    if (!ip) return "unknown";
    const address = ip.startsWith("::ffff:") ? ip.slice(7) : ip;
    if (!address.includes(":")) return address;
    return address.split(":").slice(0, 4).join(":");
}

function build({ max, windowMs = config.rateLimit.windowMs, name }) {
    if (!config.rateLimit.enabled) return (_req, _res, next) => next();

    return rateLimit({
        windowMs,
        limit: max,
        standardHeaders: "draft-7",
        legacyHeaders: false,
        // A signed-in player on a shared NAT should not be throttled because a
        // stranger on the same address is busy, so the identity is the account
        // when there is one and the normalised address when there is not.
        keyGenerator: req => (req.auth?.userId ? `user:${req.auth.userId}` : `ip:${addressKey(req.ip)}`),
        handler: (_req, _res, next) => next(tooManyRequests(`Too many ${name} requests. Wait a moment and try again.`))
    });
}

export const generalLimiter = build({ max: config.rateLimit.general, name: "API" });
export const authLimiter = build({ max: config.rateLimit.auth, name: "authentication" });
export const writeLimiter = build({ max: config.rateLimit.write, name: "write" });

export default { generalLimiter, authLimiter, writeLimiter };
