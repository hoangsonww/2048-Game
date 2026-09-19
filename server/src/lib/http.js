/**
 * Small HTTP helpers shared by every route: async error propagation, a single
 * envelope for collections, and the period windows the leaderboard is sliced
 * by.
 */
import { featureDisabled } from "./errors.js";
import config from "../config/env.js";

/**
 * Express 5 forwards a rejected promise to the error middleware on its own, but
 * wrapping remains worthwhile: it documents intent at the call site and keeps
 * the handlers working identically if they are ever mounted on a v4 router.
 */
export function asyncHandler(handler) {
    return (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);
}

/** Guards a whole router behind a deployment feature flag. */
export function requireFeature(name) {
    return (_req, _res, next) => {
        next(config.features[name] ? undefined : featureDisabled(name));
    };
}

export function collection(items, { total, limit, offset }) {
    return {
        items,
        pagination: {
            total,
            limit,
            offset,
            count: items.length,
            hasMore: offset + items.length < total
        }
    };
}

/**
 * Period windows are computed in UTC on purpose. A "daily" leaderboard that
 * rolls over at a different moment for each player is not one leaderboard, and
 * the client displays the window boundaries so the rule is visible rather than
 * folklore.
 */
export function periodWindow(period, now = new Date()) {
    const start = new Date(now);
    start.setUTCHours(0, 0, 0, 0);

    switch (period) {
        case "daily":
            break;
        case "weekly": {
            // ISO weeks start on Monday; getUTCDay() makes Sunday 0.
            const weekday = (start.getUTCDay() + 6) % 7;
            start.setUTCDate(start.getUTCDate() - weekday);
            break;
        }
        case "monthly":
            start.setUTCDate(1);
            break;
        case "yearly":
            start.setUTCMonth(0, 1);
            break;
        case "all":
        default:
            return { period: "all", since: null, until: null };
    }

    return { period, since: start, until: now };
}

export function utcDayKey(date = new Date()) {
    return date.toISOString().slice(0, 10);
}

export function noStore(res) {
    res.set("Cache-Control", "no-store");
    return res;
}

/** Public, cacheable reads get a short shared cache so the CDN absorbs bursts. */
export function publicCache(res, seconds) {
    res.set("Cache-Control", `public, max-age=0, s-maxage=${seconds}, stale-while-revalidate=${seconds * 4}`);
    return res;
}

export default { asyncHandler, requireFeature, collection, periodWindow, utcDayKey, noStore, publicCache };
