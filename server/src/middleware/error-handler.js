/**
 * The single exit for every failure.
 *
 * Driver-level and library-level errors are translated here rather than at each
 * call site, so a duplicate-key violation reads as a 409 with a useful field
 * name no matter which route provoked it, and an unrecognised error is always a
 * 500 whose internals stay on the server.
 */
import mongoose from "mongoose";
import { ApiError } from "../lib/errors.js";
import config from "../config/env.js";

function translate(error) {
    if (error instanceof ApiError) return error;

    // Duplicate key: username, email, save slot, or an idempotent re-submission.
    if (error?.code === 11000) {
        const field = Object.keys(error.keyPattern ?? error.keyValue ?? {})[0] ?? "value";
        const readable = { usernameLower: "username", email: "email address", slot: "save slot", signature: "score" }[field] ?? field;
        return new ApiError(409, "duplicate", `That ${readable} is already taken.`, { field });
    }

    if (error instanceof mongoose.Error.ValidationError) {
        return new ApiError(422, "validation_failed", "The document failed schema validation.", {
            issues: Object.entries(error.errors).map(([path, detail]) => ({ path, message: detail.message }))
        });
    }

    if (error instanceof mongoose.Error.CastError) {
        return new ApiError(400, "bad_request", `\`${error.path}\` is not a valid ${error.kind}.`);
    }

    if (error?.type === "entity.too.large") {
        return new ApiError(413, "payload_too_large", "That request body is larger than this API accepts.");
    }

    if (error?.type === "entity.parse.failed") {
        return new ApiError(400, "invalid_json", "The request body is not valid JSON.");
    }

    if (error?.name === "MongooseServerSelectionError" || error?.name === "MongoNetworkError") {
        return new ApiError(503, "database_unavailable", "The database is temporarily unreachable. Try again shortly.");
    }

    return null;
}

// eslint-disable-next-line no-unused-vars -- Express identifies error middleware by arity.
export function errorHandler(error, req, res, _next) {
    const translated = translate(error);

    if (translated) {
        if (translated.status >= 500) {
            req.log?.error("request.failed", { code: translated.code, message: translated.message });
        } else {
            req.log?.debug("request.rejected", { code: translated.code, message: translated.message });
        }
        res.status(translated.status).json({ ...translated.toJSON(), requestId: req.id });
        return;
    }

    req.log?.error("request.unhandled", { message: error?.message, stack: error?.stack });
    res.status(500).json({
        error: {
            code: "internal_error",
            message: "Something went wrong on our side.",
            // The stack is useful locally and is an information leak in
            // production, so it is gated on the environment, not on a flag
            // someone could set by accident.
            ...(config.isProduction ? {} : { debug: error?.message })
        },
        requestId: req.id
    });
}

export function notFoundHandler(req, res) {
    res.status(404).json({
        error: {
            code: "route_not_found",
            message: `No route matches ${req.method} ${req.path}.`,
            details: { documentation: "/docs" }
        },
        requestId: req.id
    });
}

export default { errorHandler, notFoundHandler };
