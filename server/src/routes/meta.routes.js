import express from "express";
import mongoose from "mongoose";
import { connectionState, pingDatabase } from "../config/database.js";
import { metricsSnapshot } from "../middleware/observability.js";
import { asyncHandler, noStore, publicCache } from "../lib/http.js";
import config from "../config/env.js";

const router = express.Router();

/**
 * Liveness is deliberately dependency-free.
 *
 * A health check that touches the database reports the database's health, not
 * the service's, and a platform that restarts the function because Atlas had a
 * slow second has made an outage worse. Readiness is the endpoint that answers
 * the dependency question, and it is separate for exactly that reason.
 */
router.get("/health", (_req, res) => {
    noStore(res).json({
        status: "ok",
        service: config.serviceName,
        version: config.version,
        environment: config.environment,
        uptimeSeconds: Math.round(process.uptime()),
        time: new Date().toISOString()
    });
});

router.get(
    "/ready",
    asyncHandler(async (_req, res) => {
        try {
            const latencyMs = await pingDatabase();
            noStore(res).json({
                status: "ready",
                database: { state: connectionState(), latencyMs: Number(latencyMs.toFixed(2)), name: config.mongo.dbName }
            });
        } catch (error) {
            noStore(res).status(503).json({
                status: "not_ready",
                database: { state: connectionState(), error: error.message }
            });
        }
    })
);

router.get("/version", (_req, res) => {
    publicCache(res, 300).json({
        service: config.serviceName,
        version: config.version,
        commit: config.commit,
        node: process.version,
        mongoose: mongoose.version,
        environment: config.environment
    });
});

/**
 * Public client configuration.
 *
 * A client reads this once at start-up instead of hard-coding limits that the
 * server also enforces. When a limit changes, one deployment changes it
 * everywhere rather than three app releases disagreeing about it.
 */
router.get("/config", (_req, res) => {
    publicCache(res, 60).json({
        service: config.serviceName,
        version: config.version,
        features: config.features,
        limits: {
            pageSizeDefault: config.limits.pageSizeDefault,
            pageSizeMax: config.limits.pageSizeMax,
            maxSaveSlots: config.limits.maxSaveSlots,
            maxScoreValue: config.limits.maxScoreValue,
            maxEventsPerBatch: config.limits.maxEventsPerBatch
        },
        auth: {
            accessTtlSeconds: config.auth.accessTtlSeconds,
            refreshTtlSeconds: config.auth.refreshTtlSeconds,
            passwordPolicy: "At least 8 characters, including one letter and one number."
        },
        documentation: { swagger: "/docs", redoc: "/redoc", reference: "/reference", openapi: "/openapi.json" }
    });
});

router.get("/metrics", (_req, res) => {
    noStore(res).json({
        // Stated explicitly: these counters belong to one warm serverless
        // instance and reset when it recycles. Presenting them as fleet-wide
        // totals would be a chart that quietly means something else.
        scope: "single-instance",
        ...metricsSnapshot()
    });
});

/** Prometheus exposition of the same counters, for anyone already scraping. */
router.get("/metrics.prom", (_req, res) => {
    const snapshot = metricsSnapshot();
    const lines = [
        "# HELP game2048_requests_total Requests handled by this instance.",
        "# TYPE game2048_requests_total counter",
        `game2048_requests_total ${snapshot.requests}`,
        "# HELP game2048_errors_total Responses with a 5xx status.",
        "# TYPE game2048_errors_total counter",
        `game2048_errors_total ${snapshot.errors}`,
        "# HELP game2048_request_duration_ms_avg Mean request duration.",
        "# TYPE game2048_request_duration_ms_avg gauge",
        `game2048_request_duration_ms_avg ${snapshot.averageDurationMs}`,
        "# HELP game2048_uptime_seconds Instance uptime.",
        "# TYPE game2048_uptime_seconds gauge",
        `game2048_uptime_seconds ${snapshot.uptimeSeconds}`
    ];
    for (const [status, count] of Object.entries(snapshot.byStatus)) {
        lines.push(`game2048_responses_total{status="${status}"} ${count}`);
    }
    noStore(res).type("text/plain; version=0.0.4").send(`${lines.join("\n")}\n`);
});

export default router;
