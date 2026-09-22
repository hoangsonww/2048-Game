/**
 * The Express application.
 *
 * `createApp()` returns an app and does not listen, connect, or read anything
 * from the network. That is what lets the same object be exported as a Vercel
 * function, started by `src/server.js`, and driven by supertest in a test —
 * three very different lifecycles over one definition.
 */
import express from "express";
import helmet from "helmet";
import cors from "cors";
import compression from "compression";
import config from "./config/env.js";
import logger from "./lib/logger.js";
import apiRoutes from "./routes/index.js";
import docsRoutes from "./docs/ui.js";
import { accessLog, requestId } from "./middleware/observability.js";
import { errorHandler, notFoundHandler } from "./middleware/error-handler.js";
import { generalLimiter } from "./middleware/rate-limit.js";
import { connectToDatabase } from "./config/database.js";
import "./models/index.js";

/**
 * A contributor serving the web client locally gets a different port every
 * run, so the allow-list can never name it. Loopback is permitted for that
 * reason and is safe to permit here specifically because this API is
 * bearer-token only: it sets no cookies and reads none, so a cross-origin
 * request carries no ambient authority for CORS to be protecting.
 */
function isLoopbackOrigin(origin) {
    try {
        const { hostname, protocol } = new URL(origin);
        return protocol === "http:" && (hostname === "localhost" || hostname === "127.0.0.1" || hostname === "[::1]");
    } catch (_) {
        return false;
    }
}

function corsOptions() {
    if (config.cors.allowAll) return { origin: true, credentials: false };
    return {
        origin(origin, callback) {
            // A request with no Origin is a server-to-server or same-origin
            // call — curl, a native app, the docs page itself — and is not what
            // CORS is defending against.
            if (!origin) return callback(null, true);
            callback(null, config.cors.origins.includes(origin) || isLoopbackOrigin(origin));
        },
        credentials: false
    };
}

export function createApp() {
    const app = express();

    // Vercel terminates TLS and proxies, so without this `req.ip` is the proxy
    // and every client shares one rate-limit bucket.
    app.set("trust proxy", 1);
    app.disable("x-powered-by");
    app.set("json spaces", 0);

    app.use(
        helmet({
            contentSecurityPolicy: {
                directives: {
                    defaultSrc: ["'self'"],
                    // The three documentation renderers are loaded from pinned
                    // CDN builds; the API itself serves no scripts at all.
                    scriptSrc: ["'self'", "'unsafe-inline'", "https://unpkg.com", "https://cdn.redoc.ly", "https://cdn.jsdelivr.net"],
                    styleSrc: ["'self'", "'unsafe-inline'", "https://unpkg.com", "https://fonts.googleapis.com", "https://cdn.jsdelivr.net"],
                    fontSrc: ["'self'", "https://fonts.gstatic.com", "data:"],
                    imgSrc: ["'self'", "data:", "https://hoangsonww.github.io", "https://cdn.redoc.ly"],
                    connectSrc: ["'self'"],
                    workerSrc: ["'self'", "blob:"],
                    objectSrc: ["'none'"],
                    frameAncestors: ["'none'"]
                }
            },
            crossOriginEmbedderPolicy: false,
            // The docs pages pull from CDNs; a same-origin resource policy
            // would block them without protecting anything the API exposes.
            crossOriginResourcePolicy: { policy: "cross-origin" }
        })
    );

    app.use(cors(corsOptions()));
    app.use(compression());
    app.use(express.json({ limit: config.limits.jsonBodyBytes }));
    app.use(express.urlencoded({ extended: false, limit: config.limits.jsonBodyBytes }));
    app.use(requestId);
    app.use(accessLog);
    app.use(generalLimiter);

    /**
     * Every API route needs the database, and a serverless invocation may be
     * the first one in a cold container. Connecting here rather than in each
     * handler means no route can forget, and the failure is translated into a
     * 503 by the error middleware instead of a hung request.
     */
    app.use("/api", async (_req, _res, next) => {
        try {
            await connectToDatabase();
            next();
        } catch (error) {
            next(error);
        }
    });

    app.use("/api/v1", apiRoutes);
    app.use("/", docsRoutes);

    // A bare `/health` as well as the versioned one, because uptime checkers
    // and platform probes overwhelmingly default to this path.
    app.get("/health", (_req, res) => {
        res.json({ status: "ok", service: config.serviceName, version: config.version });
    });

    // Landing on the service root should take a human to the interactive
    // reference, not a JSON directory. Machine clients already know /api/v1.
    app.get("/", (_req, res) => {
        res.redirect(302, "/docs");
    });

    app.use(notFoundHandler);
    app.use(errorHandler);

    logger.debug("app.created", { environment: config.environment });
    return app;
}

export default createApp;
