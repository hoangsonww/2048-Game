/**
 * Request identity, access logging, and an in-process metrics counter.
 *
 * The metrics are per-instance and reset when a serverless container recycles.
 * That is stated plainly on the endpoint itself rather than presented as a
 * cluster-wide figure it is not — a dashboard built on a number that quietly
 * means something else is worse than no dashboard.
 */
import crypto from "node:crypto";
import logger from "../lib/logger.js";

const METRICS_KEY = Symbol.for("2048.cloud.metrics");

function store() {
    if (!globalThis[METRICS_KEY]) {
        globalThis[METRICS_KEY] = {
            startedAt: Date.now(),
            requests: 0,
            errors: 0,
            byStatus: new Map(),
            byRoute: new Map(),
            durationTotalMs: 0
        };
    }
    return globalThis[METRICS_KEY];
}

export function metricsSnapshot() {
    const metrics = store();
    return {
        uptimeSeconds: Math.round((Date.now() - metrics.startedAt) / 1000),
        requests: metrics.requests,
        errors: metrics.errors,
        averageDurationMs: metrics.requests ? Number((metrics.durationTotalMs / metrics.requests).toFixed(2)) : 0,
        byStatus: Object.fromEntries([...metrics.byStatus.entries()].sort()),
        byRoute: Object.fromEntries([...metrics.byRoute.entries()].sort((a, b) => b[1] - a[1]).slice(0, 25))
    };
}

export function resetMetrics() {
    globalThis[METRICS_KEY] = undefined;
}

export function requestId(req, res, next) {
    const incoming = req.get("x-request-id");
    req.id = incoming && incoming.length <= 200 ? incoming : crypto.randomUUID();
    res.set("X-Request-Id", req.id);
    req.log = logger.child({ requestId: req.id });
    next();
}

export function accessLog(req, res, next) {
    const started = process.hrtime.bigint();
    res.on("finish", () => {
        const durationMs = Number(process.hrtime.bigint() - started) / 1_000_000;
        const metrics = store();
        // `req.route` is only populated once a router has matched, so the
        // template path is used when available and the raw path otherwise.
        const route = `${req.method} ${req.baseUrl ?? ""}${req.route?.path ?? req.path}`;

        metrics.requests += 1;
        metrics.durationTotalMs += durationMs;
        metrics.byStatus.set(String(res.statusCode), (metrics.byStatus.get(String(res.statusCode)) ?? 0) + 1);
        metrics.byRoute.set(route, (metrics.byRoute.get(route) ?? 0) + 1);
        if (res.statusCode >= 500) metrics.errors += 1;

        req.log?.info("http.request", {
            method: req.method,
            path: req.originalUrl,
            status: res.statusCode,
            durationMs: Number(durationMs.toFixed(2)),
            client: req.get("x-client") ?? "unknown"
        });
    });
    next();
}

export default { requestId, accessLog, metricsSnapshot, resetMetrics };
