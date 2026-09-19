/**
 * A structured logger small enough to have no dependency.
 *
 * Vercel ingests stdout line by line and parses JSON, so one JSON object per
 * line is all a log transport needs to be here. Credentials and tokens are
 * redacted by key name rather than by call site, because a redaction that
 * depends on every caller remembering it is not a redaction.
 */
const LEVELS = { silent: 100, error: 50, warn: 40, info: 30, debug: 20 };

const REDACTED_KEYS = new Set([
    "password", "currentPassword", "newPassword", "passwordHash",
    "token", "accessToken", "refreshToken", "authorization", "cookie",
    "secret", "mongodbUri", "uri"
]);

function redact(value, depth = 0) {
    if (value === null || typeof value !== "object" || depth > 4) return value;
    if (Array.isArray(value)) return value.slice(0, 20).map(entry => redact(entry, depth + 1));
    const output = {};
    for (const [key, entry] of Object.entries(value)) {
        output[key] = REDACTED_KEYS.has(key) ? "[redacted]" : redact(entry, depth + 1);
    }
    return output;
}

function levelValue(name) {
    return LEVELS[name] ?? LEVELS.info;
}

function emit(level, event, context, threshold) {
    if (levelValue(level) < levelValue(threshold)) return;
    const line = JSON.stringify({
        level,
        event,
        time: new Date().toISOString(),
        ...redact(context ?? {})
    });
    if (level === "error") process.stderr.write(`${line}\n`);
    else process.stdout.write(`${line}\n`);
}

export function createLogger(threshold = "info") {
    return {
        threshold,
        error: (event, context) => emit("error", event, context, threshold),
        warn: (event, context) => emit("warn", event, context, threshold),
        info: (event, context) => emit("info", event, context, threshold),
        debug: (event, context) => emit("debug", event, context, threshold),
        child: extra => {
            const base = createLogger(threshold);
            return {
                threshold,
                error: (event, context) => base.error(event, { ...extra, ...context }),
                warn: (event, context) => base.warn(event, { ...extra, ...context }),
                info: (event, context) => base.info(event, { ...extra, ...context }),
                debug: (event, context) => base.debug(event, { ...extra, ...context }),
                child: more => createLogger(threshold).child({ ...extra, ...more })
            };
        }
    };
}

const logger = createLogger(process.env.LOG_LEVEL ?? (process.env.NODE_ENV === "test" ? "silent" : "info"));

export default logger;
