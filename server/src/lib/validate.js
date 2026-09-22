/**
 * Request validation.
 *
 * Every route validates with a Zod schema and then reads only the *parsed*
 * value. Reading `req.body` directly after validating is the subtle mistake
 * this wrapper exists to prevent: the parsed object is coerced, defaulted, and
 * stripped of unknown keys, and the raw one is none of those things.
 */
import { z } from "zod";
import config from "../config/env.js";
import { validationFailed } from "./errors.js";

export { z };

function describe(error) {
    return error.issues.map(issue => ({
        path: issue.path.join(".") || "(root)",
        code: issue.code,
        message: issue.message
    }));
}

function parseInto(target, schema, req) {
    const result = schema.safeParse(req[target]);
    if (!result.success) throw validationFailed({ in: target, issues: describe(result.error) });
    req.valid ??= {};
    req.valid[target] = result.data;
}

/**
 * @param {{body?: import("zod").ZodTypeAny, query?: import("zod").ZodTypeAny, params?: import("zod").ZodTypeAny}} schemas
 */
export function validate(schemas) {
    return (req, _res, next) => {
        try {
            if (schemas.params) parseInto("params", schemas.params, req);
            if (schemas.query) parseInto("query", schemas.query, req);
            if (schemas.body) parseInto("body", schemas.body, req);
            next();
        } catch (error) {
            next(error);
        }
    };
}

/* ---------------------------------------------------------------------- */
/* Reusable field schemas                                                   */
/* ---------------------------------------------------------------------- */

/**
 * Usernames are the public identity, so they are restricted to characters that
 * survive a URL, a leaderboard row, and a screen reader without surprises.
 */
export const usernameSchema = z
    .string()
    .trim()
    .min(3, "A username needs at least 3 characters.")
    .max(24, "A username can be at most 24 characters.")
    .regex(/^[a-zA-Z0-9][a-zA-Z0-9_.-]*[a-zA-Z0-9]$/, "Use letters, numbers, dots, dashes, and underscores; start and end with a letter or number.");

export const emailSchema = z.string().trim().toLowerCase().email("That does not look like an email address.").max(254);

export const passwordSchema = z
    .string()
    .min(8, "A password needs at least 8 characters.")
    .max(200, "A password can be at most 200 characters.")
    .refine(value => /[a-zA-Z]/.test(value) && /[0-9]/.test(value), "Include at least one letter and one number.");

export const displayNameSchema = z.string().trim().min(1).max(40);

export const boardSchema = z.union([
    z.array(z.number().int().min(0)).length(16),
    z.array(z.array(z.number().int().min(0)).length(4)).length(4)
]);

export const scoreValueSchema = z.number().int().min(0).max(config.limits.maxScoreValue);

export const slotSchema = z
    .string()
    .trim()
    .min(1)
    .max(32)
    .regex(/^[a-z0-9][a-z0-9_-]*$/i, "A slot name may contain letters, numbers, dashes, and underscores.");

export const clientSchema = z.enum(["web", "ios", "android", "cli", "unknown"]).default("unknown");

export const isoDateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Use an ISO date of the form YYYY-MM-DD.");

export const objectIdSchema = z.string().regex(/^[a-f\d]{24}$/i, "That is not a valid identifier.");

/** Cursorless pagination: the dataset is small, ranked, and read by page number. */
export const paginationSchema = z.object({
    limit: z.coerce.number().int().min(1).max(config.limits.pageSizeMax).default(config.limits.pageSizeDefault),
    offset: z.coerce.number().int().min(0).max(100_000).default(0)
});

export const periodSchema = z.enum(["daily", "weekly", "monthly", "yearly", "all"]).default("all");

export default validate;
