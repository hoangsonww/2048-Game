import express from "express";
import metaRoutes from "./meta.routes.js";
import authRoutes from "./auth.routes.js";
import userRoutes from "./users.routes.js";
import saveRoutes from "./saves.routes.js";
import scoreRoutes from "./scores.routes.js";
import leaderboardRoutes from "./leaderboard.routes.js";
import achievementRoutes from "./achievements.routes.js";
import statsRoutes from "./stats.routes.js";
import socialRoutes from "./social.routes.js";
import challengeRoutes from "./challenges.routes.js";
import eventRoutes from "./events.routes.js";
import { authLimiter, writeLimiter } from "../middleware/rate-limit.js";

export const API_BASE = "/api/v1";

/**
 * The mount table, exported rather than inlined into `router.use(...)` calls.
 *
 * Express 5 does not expose a mounted router's prefix, so a test cannot
 * reconstruct the full path set by walking the app. Declaring the table as
 * data means `tests/unit/openapi.test.js` can read exactly what the app
 * mounts, and the contract test that compares code against the OpenAPI
 * document has a real source rather than a second hand-maintained list.
 */
export const ROUTE_TABLE = Object.freeze([
    { prefix: "", router: metaRoutes, middleware: [] },
    { prefix: "/auth", router: authRoutes, middleware: [authLimiter] },
    { prefix: "/users", router: userRoutes, middleware: [] },
    { prefix: "/saves", router: saveRoutes, middleware: [writeLimiter] },
    { prefix: "/scores", router: scoreRoutes, middleware: [writeLimiter] },
    { prefix: "/leaderboard", router: leaderboardRoutes, middleware: [] },
    { prefix: "/achievements", router: achievementRoutes, middleware: [] },
    { prefix: "/stats", router: statsRoutes, middleware: [] },
    { prefix: "/social", router: socialRoutes, middleware: [writeLimiter] },
    { prefix: "/challenges", router: challengeRoutes, middleware: [] },
    { prefix: "/events", router: eventRoutes, middleware: [writeLimiter] }
]);

/**
 * Enumerates every `METHOD /api/v1/...` the app serves.
 *
 * Relative paths inside a router *are* introspectable; only the mount prefix
 * is not, which is what `ROUTE_TABLE` supplies.
 */
export function mountedRoutes() {
    const routes = [];
    for (const { prefix, router } of ROUTE_TABLE) {
        for (const layer of router.stack) {
            if (!layer.route) continue;
            const path = layer.route.path === "/" ? "" : layer.route.path;
            for (const [method, enabled] of Object.entries(layer.route.methods)) {
                if (!enabled || method === "_all") continue;
                routes.push({ method: method.toUpperCase(), path: `${API_BASE}${prefix}${path}` || API_BASE });
            }
        }
    }
    return routes;
}

/**
 * The v1 surface.
 *
 * Versioning is by path rather than by header. A player debugging their own
 * client should be able to paste a URL into a browser and see what the app
 * sees; a version negotiated in a header makes that impossible.
 */
const router = express.Router();

for (const { prefix, router: child, middleware } of ROUTE_TABLE) {
    router.use(prefix || "/", ...middleware, child);
}

export default router;
