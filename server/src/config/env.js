/**
 * Configuration is read once, validated once, and frozen.
 *
 * A serverless invocation that discovers a missing secret halfway through a
 * request fails in a way that is hard to read in a log. Failing at import time
 * instead turns a misconfigured deployment into one obvious error.
 */
import crypto from "node:crypto";

const truthy = new Set(["1", "true", "yes", "on"]);

function flag(name, fallback = false) {
    const raw = process.env[name];
    if (raw === undefined || raw === "") return fallback;
    return truthy.has(raw.toLowerCase());
}

function integer(name, fallback) {
    const raw = Number.parseInt(process.env[name] ?? "", 10);
    return Number.isFinite(raw) ? raw : fallback;
}

function list(name, fallback = []) {
    const raw = (process.env[name] ?? "").trim();
    if (!raw) return fallback;
    return raw.split(",").map(entry => entry.trim()).filter(Boolean);
}

const environment = process.env.NODE_ENV ?? "development";
const isProduction = environment === "production";
const isTest = environment === "test";

/**
 * A development or test run should not require a secret to be invented before
 * the server will boot, but a production deployment absolutely must have one.
 * An ephemeral secret invalidates every token on restart, which is correct
 * behaviour for a throwaway environment and catastrophic for a real one.
 */
function secret(name, purpose) {
    const value = process.env[name];
    if (value && value.length >= 16) return value;
    if (isProduction) {
        throw new Error(`${name} must be set to at least 16 characters in production (${purpose}).`);
    }
    return crypto.randomBytes(32).toString("hex");
}

export const config = Object.freeze({
    environment,
    isProduction,
    isTest,
    port: integer("PORT", 4000),
    serviceName: "2048-cloud-api",
    version: process.env.API_VERSION ?? "2.1.0",
    commit: process.env.VERCEL_GIT_COMMIT_SHA ?? process.env.GIT_COMMIT ?? "local",
    publicUrl: process.env.PUBLIC_URL ?? (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : `http://localhost:${integer("PORT", 4000)}`),

    mongo: Object.freeze({
        uri: process.env.MONGODB_URI ?? "",
        dbName: process.env.MONGODB_DB ?? "game2048",
        serverSelectionTimeoutMS: integer("MONGODB_TIMEOUT_MS", 10_000),
        maxPoolSize: integer("MONGODB_POOL_SIZE", 5)
    }),

    auth: Object.freeze({
        accessSecret: secret("JWT_ACCESS_SECRET", "signs access tokens"),
        refreshSecret: secret("JWT_REFRESH_SECRET", "signs refresh tokens"),
        accessTtlSeconds: integer("JWT_ACCESS_TTL", 60 * 60),
        refreshTtlSeconds: integer("JWT_REFRESH_TTL", 60 * 60 * 24 * 60),
        issuer: process.env.JWT_ISSUER ?? "2048-cloud-api",
        audience: process.env.JWT_AUDIENCE ?? "2048-clients",
        bcryptRounds: integer("BCRYPT_ROUNDS", isTest ? 4 : 11),
        maxSessionsPerUser: integer("MAX_SESSIONS_PER_USER", 20)
    }),

    cors: Object.freeze({
        // The web client is served from GitHub Pages and from any local port a
        // contributor happens to use, so the allow-list is explicit rather than
        // a blanket wildcard, and `*` stays available for deliberate opt-in.
        origins: list("CORS_ORIGINS", [
            "https://hoangsonww.github.io",
            "https://the-2048.netlify.app",
            "http://localhost:8080",
            "http://127.0.0.1:8080",
            "http://localhost:4000",
            "http://localhost:5173"
        ]),
        allowAll: flag("CORS_ALLOW_ALL", !isProduction)
    }),

    limits: Object.freeze({
        jsonBodyBytes: integer("MAX_JSON_BODY_BYTES", 64 * 1024),
        pageSizeDefault: integer("PAGE_SIZE_DEFAULT", 25),
        pageSizeMax: integer("PAGE_SIZE_MAX", 100),
        maxSaveSlots: integer("MAX_SAVE_SLOTS", 10),
        maxScoreValue: integer("MAX_SCORE_VALUE", 20_000_000),
        maxEventsPerBatch: integer("MAX_EVENTS_PER_BATCH", 50)
    }),

    rateLimit: Object.freeze({
        enabled: flag("RATE_LIMIT_ENABLED", !isTest),
        windowMs: integer("RATE_LIMIT_WINDOW_MS", 60_000),
        general: integer("RATE_LIMIT_GENERAL", 240),
        auth: integer("RATE_LIMIT_AUTH", 20),
        write: integer("RATE_LIMIT_WRITE", 90)
    }),

    features: Object.freeze({
        registrationOpen: flag("FEATURE_REGISTRATION", true),
        leaderboards: flag("FEATURE_LEADERBOARDS", true),
        cloudSaves: flag("FEATURE_CLOUD_SAVES", true),
        social: flag("FEATURE_SOCIAL", true),
        dailyChallenge: flag("FEATURE_DAILY_CHALLENGE", true),
        events: flag("FEATURE_EVENTS", true),
        // Self-service reset without an email round trip. See the endpoint's
        // own comment: anyone who knows a username and its email address can
        // take the account over, so this is a switch a deployment can throw.
        passwordReset: flag("FEATURE_PASSWORD_RESET", true)
    }),

    logLevel: process.env.LOG_LEVEL ?? (isTest ? "silent" : "info")
});

export default config;
