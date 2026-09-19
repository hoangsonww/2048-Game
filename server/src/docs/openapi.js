/**
 * The OpenAPI 3.1 description of this API.
 *
 * It is a single document built in code rather than a scatter of JSDoc
 * annotations, for one reason: a reference page is read top to bottom by a
 * human deciding whether to use the API, and that reading order is impossible
 * to control when the source is comment fragments distributed across a dozen
 * route files. Here the tag order, the prose, and the examples are all
 * deliberate.
 *
 * `tests/unit/openapi.test.js` asserts that every route the Express app mounts
 * appears here, so the document cannot silently fall behind the code.
 */
import config from "../config/env.js";
import schemas from "./schemas.js";

const BASE = "/api/v1";

/* ---------------------------------------------------------------------- */
/* Builders                                                                */
/* ---------------------------------------------------------------------- */

const ref = name => ({ $ref: `#/components/schemas/${name}` });

const body = (schema, { required = true, description } = {}) => ({
    required,
    ...(description ? { description } : {}),
    content: { "application/json": { schema } }
});

const response = (description, schema) => ({
    description,
    ...(schema ? { content: { "application/json": { schema } } } : {})
});

const errorResponse = description => response(description, ref("Error"));

const query = (name, schema, description, extra = {}) => ({ name, in: "query", schema, description, ...extra });
const pathParam = (name, schema, description) => ({ name, in: "path", required: true, schema, description });

const PAGINATION_PARAMS = [
    query("limit", { type: "integer", minimum: 1, maximum: config.limits.pageSizeMax, default: config.limits.pageSizeDefault }, "Page size."),
    query("offset", { type: "integer", minimum: 0, default: 0 }, "Rows to skip.")
];

const PERIOD_PARAM = query(
    "period",
    { type: "string", enum: ["daily", "weekly", "monthly", "yearly", "all"], default: "all" },
    "Window to rank within. All windows are UTC; `GET /leaderboard/periods` returns the exact boundaries."
);

const MODE_PARAM = query("mode", { type: "string", enum: ["classic", "daily"], default: "classic" }, "Which board to read.");

/**
 * @param {object} spec
 * @param {string} spec.tag
 * @param {string} spec.summary
 * @param {string} [spec.description]
 * @param {boolean} [spec.auth]
 */
function operation({ tag, summary, description, auth = false, parameters, requestBody, responses, operationId }) {
    return {
        tags: [tag],
        operationId,
        summary,
        ...(description ? { description } : {}),
        ...(auth ? { security: [{ bearerAuth: [] }] } : { security: [] }),
        ...(parameters ? { parameters } : {}),
        ...(requestBody ? { requestBody } : {}),
        responses: {
            ...responses,
            "422": errorResponse("The request failed validation. `error.details.issues` names each offending field."),
            ...(auth ? { "401": errorResponse("Missing, expired, or malformed access token.") } : {}),
            "429": errorResponse("Rate limit exceeded."),
            "500": errorResponse("Unhandled server error.")
        }
    };
}

/* ---------------------------------------------------------------------- */
/* Paths                                                                    */
/* ---------------------------------------------------------------------- */

const metaPaths = {
    [`${BASE}/health`]: {
        get: operation({
            tag: "Meta",
            operationId: "getHealth",
            summary: "Liveness",
            description:
                "Answers whether the process is running. It deliberately does **not** touch the database: a health check that fails because a dependency is slow invites a platform to restart a service that was fine. Use `/ready` for the dependency question.",
            responses: { "200": response("The service is running.", { type: "object", properties: { status: { type: "string", example: "ok" }, version: { type: "string" }, uptimeSeconds: { type: "integer" } } }) }
        })
    },
    [`${BASE}/ready`]: {
        get: operation({
            tag: "Meta",
            operationId: "getReadiness",
            summary: "Readiness, including a database ping",
            responses: {
                "200": response("The database answered.", { type: "object", properties: { status: { type: "string" }, database: { type: "object", additionalProperties: true } } }),
                "503": response("The database is unreachable.", { type: "object", additionalProperties: true })
            }
        })
    },
    [`${BASE}/version`]: {
        get: operation({ tag: "Meta", operationId: "getVersion", summary: "Build and runtime versions", responses: { "200": response("Version information.", { type: "object", additionalProperties: true }) } })
    },
    [`${BASE}/config`]: {
        get: operation({
            tag: "Meta",
            operationId: "getClientConfig",
            summary: "Public client configuration",
            description: "Feature flags and limits, read once at start-up so clients do not hard-code values the server also enforces.",
            responses: { "200": response("Client configuration.", { type: "object", additionalProperties: true }) }
        })
    },
    [`${BASE}/metrics`]: {
        get: operation({
            tag: "Meta",
            operationId: "getMetrics",
            summary: "Request counters for this instance",
            description: "Counters belong to one warm serverless instance and reset when it recycles. They are not fleet-wide totals.",
            responses: { "200": response("Counters.", { type: "object", additionalProperties: true }) }
        })
    },
    [`${BASE}/metrics.prom`]: {
        get: operation({
            tag: "Meta",
            operationId: "getPrometheusMetrics",
            summary: "The same counters in Prometheus exposition format",
            responses: { "200": { description: "Prometheus text.", content: { "text/plain": { schema: { type: "string" } } } } }
        })
    }
};

const authPaths = {
    [`${BASE}/auth/register`]: {
        post: operation({
            tag: "Authentication",
            operationId: "register",
            summary: "Create an account",
            description: "Returns a token pair immediately, so a player who signs up mid-round can sync without a second request.",
            requestBody: body({
                type: "object",
                required: ["username", "email", "password"],
                properties: {
                    username: { type: "string", minLength: 3, maxLength: 24, example: "ada" },
                    email: { type: "string", format: "email", example: "ada@example.com" },
                    password: { type: "string", minLength: 8, description: "At least 8 characters, including one letter and one number." },
                    displayName: { type: "string", maxLength: 40 },
                    country: { type: "string", minLength: 2, maxLength: 2, example: "GB" },
                    client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] }
                }
            }),
            responses: {
                "201": response("Account created and signed in.", ref("AuthResponse")),
                "409": errorResponse("The username or email address is already taken. `error.details.field` says which."),
                "403": errorResponse("Registration is closed on this deployment.")
            }
        })
    },
    [`${BASE}/auth/login`]: {
        post: operation({
            tag: "Authentication",
            operationId: "login",
            summary: "Sign in",
            description: "An unknown account and a wrong password return the same error, so this endpoint cannot be used to discover who has an account.",
            requestBody: body({
                type: "object",
                required: ["identifier", "password"],
                properties: {
                    identifier: { type: "string", description: "Username or email address.", example: "ada" },
                    password: { type: "string" },
                    client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] }
                }
            }),
            responses: { "200": response("Signed in.", ref("AuthResponse")), "401": errorResponse("Invalid credentials.") }
        })
    },
    [`${BASE}/auth/refresh`]: {
        post: operation({
            tag: "Authentication",
            operationId: "refresh",
            summary: "Rotate a token pair",
            description: "Refresh tokens are single-use. Replaying a rotated token revokes the whole session, which is what turns a stolen token into a detectable event rather than a silent one.",
            requestBody: body({ type: "object", required: ["refreshToken"], properties: { refreshToken: { type: "string" } } }),
            responses: { "200": response("A fresh pair.", ref("AuthResponse")), "401": errorResponse("The session is gone, expired, or the token was already rotated.") }
        })
    },
    [`${BASE}/auth/logout`]: {
        post: operation({
            tag: "Authentication",
            operationId: "logout",
            summary: "Revoke one session",
            requestBody: body({ type: "object", properties: { refreshToken: { type: "string" } } }, { required: false }),
            responses: { "200": response("Signed out.", { type: "object", properties: { signedOut: { type: "boolean" } } }) }
        })
    },
    [`${BASE}/auth/logout-all`]: {
        post: operation({
            tag: "Authentication",
            operationId: "logoutAll",
            summary: "Revoke every session on the account",
            auth: true,
            responses: { "200": response("All sessions revoked.", { type: "object", properties: { signedOut: { type: "boolean" }, sessionsRevoked: { type: "integer" } } }) }
        })
    },
    [`${BASE}/auth/me`]: {
        get: operation({ tag: "Authentication", operationId: "getCurrentUser", summary: "The signed-in account", auth: true, responses: { "200": response("The account.", { type: "object", properties: { user: ref("PrivateUser") } }) } }),
        patch: operation({
            tag: "Authentication",
            operationId: "updateCurrentUser",
            summary: "Update profile fields",
            auth: true,
            requestBody: body({
                type: "object",
                properties: {
                    displayName: { type: "string", maxLength: 40 },
                    country: { type: "string", minLength: 2, maxLength: 2, nullable: true },
                    avatarColor: { type: "string", pattern: "^#[0-9a-fA-F]{6}$" },
                    bio: { type: "string", maxLength: 280 }
                }
            }),
            responses: { "200": response("Updated.", { type: "object", properties: { user: ref("PrivateUser") } }) }
        }),
        delete: operation({
            tag: "Authentication",
            operationId: "deleteAccount",
            summary: "Delete the account and every trace of it",
            description: "Removes the account, its sessions, saves, scores, achievements, follows, and telemetry in one request. There is no tombstone and no recovery window.",
            auth: true,
            requestBody: body({ type: "object", required: ["password", "confirm"], properties: { password: { type: "string" }, confirm: { type: "string", enum: ["DELETE"] } } }),
            responses: { "200": response("Deleted.", { type: "object", properties: { deleted: { type: "boolean" } } }), "401": errorResponse("The password is wrong.") }
        })
    },
    [`${BASE}/auth/change-password`]: {
        post: operation({
            tag: "Authentication",
            operationId: "changePassword",
            summary: "Change the password",
            description: "By default every other session is revoked, because a password change that leaves other devices signed in is not a password change.",
            auth: true,
            requestBody: body({
                type: "object",
                required: ["currentPassword", "newPassword"],
                properties: { currentPassword: { type: "string" }, newPassword: { type: "string", minLength: 8 }, signOutOtherSessions: { type: "boolean", default: true } }
            }),
            responses: { "200": response("Changed.", { type: "object", properties: { changed: { type: "boolean" }, sessionsRevoked: { type: "integer" } } }), "401": errorResponse("The current password is wrong.") }
        })
    },
    [`${BASE}/auth/sessions`]: {
        get: operation({ tag: "Authentication", operationId: "listSessions", summary: "List signed-in devices", auth: true, responses: { "200": response("Sessions, newest first.", { type: "object", properties: { items: { type: "array", items: ref("Session") } } }) } })
    },
    [`${BASE}/auth/sessions/{sessionId}`]: {
        delete: operation({
            tag: "Authentication",
            operationId: "revokeSession",
            summary: "Revoke one device",
            auth: true,
            parameters: [pathParam("sessionId", { type: "string", format: "uuid" }, "Session identifier from `GET /auth/sessions`.")],
            responses: { "200": response("Revoked.", { type: "object", properties: { revoked: { type: "boolean" }, id: { type: "string" } } }), "404": errorResponse("No such session on this account.") }
        })
    },
    [`${BASE}/auth/available`]: {
        get: operation({
            tag: "Authentication",
            operationId: "checkAvailability",
            summary: "Check whether a username or email is free",
            description: "Intended for inline validation on a sign-up form. The unique indexes remain the real guarantee; this is a better error message, not the enforcement.",
            parameters: [query("username", { type: "string" }, "Username to test."), query("email", { type: "string", format: "email" }, "Email address to test.")],
            responses: { "200": response("Availability.", { type: "object", additionalProperties: true }) }
        })
    }
};

const userPaths = {
    [`${BASE}/users`]: {
        get: operation({
            tag: "Players",
            operationId: "listPlayers",
            summary: "Search players",
            description: "Matching is an anchored prefix on the username so the query uses an index rather than scanning the collection on every keystroke.",
            parameters: [...PAGINATION_PARAMS, query("q", { type: "string" }, "Username prefix."), query("sort", { type: "string", enum: ["best", "recent", "name"], default: "best" }, "Ordering.")],
            responses: { "200": response("Matching players.", { type: "object", properties: { items: { type: "array", items: ref("PublicUser") }, pagination: ref("Pagination") } }) }
        })
    },
    [`${BASE}/users/me/preferences`]: {
        get: operation({ tag: "Players", operationId: "getPreferences", summary: "Read preferences", auth: true, responses: { "200": response("Preferences.", { type: "object", properties: { preferences: ref("Preferences") } }) } }),
        put: operation({
            tag: "Players",
            operationId: "updatePreferences",
            summary: "Update preferences",
            auth: true,
            requestBody: body(ref("Preferences")),
            responses: { "200": response("Updated.", { type: "object", properties: { preferences: ref("Preferences") } }) }
        })
    },
    [`${BASE}/users/me/export`]: {
        get: operation({
            tag: "Players",
            operationId: "exportAccountData",
            summary: "Download everything stored about the account",
            description: "The counterpart to account deletion: data about a player should be theirs to read as well as theirs to remove.",
            auth: true,
            responses: { "200": response("A JSON export.", { type: "object", additionalProperties: true }) }
        })
    },
    [`${BASE}/users/{username}`]: {
        get: operation({
            tag: "Players",
            operationId: "getPlayer",
            summary: "A public profile",
            parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")],
            responses: { "200": response("The profile.", { type: "object", properties: { user: ref("PublicUser"), isSelf: { type: "boolean" } } }), "404": errorResponse("No such player.") }
        })
    },
    [`${BASE}/users/{username}/scores`]: {
        get: operation({
            tag: "Players",
            operationId: "getPlayerScores",
            summary: "A player's best rounds",
            parameters: [pathParam("username", { type: "string" }, "Case-insensitive username."), ...PAGINATION_PARAMS],
            responses: { "200": response("Scores, highest first.", { type: "object", properties: { items: { type: "array", items: ref("Score") }, pagination: ref("Pagination") } }), "403": errorResponse("That profile is private."), "404": errorResponse("No such player.") }
        })
    },
    [`${BASE}/users/{username}/achievements`]: {
        get: operation({
            tag: "Players",
            operationId: "getPlayerAchievements",
            summary: "A player's achievements",
            parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")],
            responses: { "200": response("Achievements and a completion summary.", { type: "object", properties: { items: { type: "array", items: ref("Achievement") }, summary: { type: "object", additionalProperties: true } } }), "403": errorResponse("That profile is private."), "404": errorResponse("No such player.") }
        })
    },
    [`${BASE}/users/{username}/stats`]: {
        get: operation({
            tag: "Players",
            operationId: "getPlayerStats",
            summary: "A player's statistics",
            parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")],
            responses: { "200": response("Statistics.", ref("PersonalStats")), "403": errorResponse("That profile is private."), "404": errorResponse("No such player.") }
        })
    }
};

const savePaths = {
    [`${BASE}/saves`]: {
        get: operation({ tag: "Cloud saves", operationId: "listSaves", summary: "List every slot", auth: true, responses: { "200": response("Slots, most recently updated first.", { type: "object", properties: { items: { type: "array", items: ref("GameSave") }, limits: { type: "object", additionalProperties: true } } }) } }),
        delete: operation({
            tag: "Cloud saves",
            operationId: "deleteAllSaves",
            summary: "Delete every slot",
            auth: true,
            requestBody: body({ type: "object", required: ["confirm"], properties: { confirm: { type: "string", enum: ["DELETE"] } } }),
            responses: { "200": response("Deleted.", { type: "object", properties: { deleted: { type: "boolean" }, count: { type: "integer" } } }) }
        })
    },
    [`${BASE}/saves/sync`]: {
        post: operation({
            tag: "Cloud saves",
            operationId: "syncSave",
            summary: "Two-way synchronisation",
            description:
                "The endpoint to call on launch, on sign-in, and on reconnect — the only one that can reconcile two devices without losing a round.\n\n" +
                "Resolution order: no remote save uploads the local one; no local save downloads the remote one; identical rounds report `in_sync`; " +
                "a local save carrying a `baseRevision` at or above the stored revision is a continuation and uploads; otherwise the further round (score, then moves) wins and **the other is preserved in a `conflict-…` slot**. Nothing is discarded.",
            auth: true,
            requestBody: body({
                type: "object",
                properties: {
                    slot: { type: "string", default: "current" },
                    strategy: { type: "string", enum: ["auto", "prefer-local", "prefer-remote"], default: "auto", description: "`auto` applies the resolution order above. The other two are for an explicit user choice after a conflict." },
                    save: { oneOf: [ref("SavePayload"), { type: "null" }], description: "The device's local save, or null when it has none." }
                }
            }),
            responses: { "200": response("Resolved.", ref("SyncResult")) }
        })
    },
    [`${BASE}/saves/current`]: {
        get: operation({ tag: "Cloud saves", operationId: "getCurrentSave", summary: "Read the active round", auth: true, responses: { "200": response("The save.", { type: "object", properties: { save: ref("GameSave") } }), "404": errorResponse("No cloud save yet.") } }),
        put: operation({
            tag: "Cloud saves",
            operationId: "putCurrentSave",
            summary: "Overwrite the active round",
            description: "Unconditional: the caller's save wins. Use `POST /saves/sync` unless the player has explicitly chosen this device's round.",
            auth: true,
            requestBody: body(ref("SavePayload")),
            responses: { "200": response("Stored.", { type: "object", properties: { save: ref("GameSave"), resolution: { type: "string" } } }) }
        })
    },
    [`${BASE}/saves/{slot}`]: {
        get: operation({ tag: "Cloud saves", operationId: "getSave", summary: "Read a slot", auth: true, parameters: [pathParam("slot", { type: "string" }, "Slot name.")], responses: { "200": response("The save.", { type: "object", properties: { save: ref("GameSave") } }), "404": errorResponse("No such slot.") } }),
        put: operation({
            tag: "Cloud saves",
            operationId: "putSave",
            summary: "Create or overwrite a slot",
            auth: true,
            parameters: [pathParam("slot", { type: "string" }, "Slot name.")],
            requestBody: body(ref("SavePayload")),
            responses: { "200": response("Updated.", { type: "object", properties: { save: ref("GameSave") } }), "201": response("Created.", { type: "object", properties: { save: ref("GameSave") } }), "409": errorResponse("The slot limit for this account is already reached.") }
        }),
        delete: operation({ tag: "Cloud saves", operationId: "deleteSave", summary: "Delete a slot", auth: true, parameters: [pathParam("slot", { type: "string" }, "Slot name.")], responses: { "200": response("Deleted.", { type: "object", properties: { deleted: { type: "boolean" }, slot: { type: "string" } } }), "404": errorResponse("No such slot.") } })
    }
};

const scorePaths = {
    [`${BASE}/scores`]: {
        post: operation({
            tag: "Scores",
            operationId: "submitScore",
            summary: "Submit a finished round",
            description:
                "Idempotent: the same board and score from the same player returns the original row with `duplicate: true` and a 200 rather than creating a second leaderboard entry, so a retry after a flaky network is safe.\n\n" +
                "A score that exceeds what its final board could have produced is stored with `verified: false` and kept out of every leaderboard. It is flagged rather than refused, because refusing would lose a genuine round to a client bug.",
            auth: true,
            requestBody: body({
                type: "object",
                required: ["score"],
                properties: {
                    board: ref("Board"),
                    grid: ref("Board"),
                    score: { type: "integer", minimum: 0 },
                    moves: { type: "integer", minimum: 0 },
                    durationSeconds: { type: "integer", minimum: 0 },
                    mode: { type: "string", enum: ["classic", "daily"], default: "classic" },
                    challengeDate: { type: "string", nullable: true },
                    client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] }
                }
            }),
            responses: {
                "201": response("Recorded.", { type: "object", properties: { score: ref("Score"), duplicate: { type: "boolean" }, unlockedAchievements: { type: "array", items: ref("Achievement") }, statistics: ref("Statistics") } }),
                "200": response("Already recorded; the original row is returned.", { type: "object", properties: { score: ref("Score"), duplicate: { type: "boolean" } } })
            }
        }),
        get: operation({
            tag: "Scores",
            operationId: "listMyScores",
            summary: "The signed-in player's rounds",
            auth: true,
            parameters: [
                ...PAGINATION_PARAMS,
                query("mode", { type: "string", enum: ["classic", "daily", "all"], default: "all" }, "Filter by mode."),
                query("sort", { type: "string", enum: ["recent", "score"], default: "recent" }, "Ordering."),
                query("wonOnly", { type: "boolean", default: false }, "Only rounds that reached 2048.")
            ],
            responses: { "200": response("Rounds.", { type: "object", properties: { items: { type: "array", items: ref("Score") }, pagination: ref("Pagination") } }) }
        })
    },
    [`${BASE}/scores/best`]: {
        get: operation({ tag: "Scores", operationId: "getPersonalBest", summary: "Personal best", auth: true, responses: { "200": response("The best verified round, or null.", { type: "object", properties: { best: { oneOf: [ref("Score"), { type: "null" }] } } }) } })
    },
    [`${BASE}/scores/stats`]: {
        get: operation({ tag: "Scores", operationId: "getMyScoreStats", summary: "Career statistics", auth: true, responses: { "200": response("Statistics.", ref("PersonalStats")) } })
    },
    [`${BASE}/scores/{id}`]: {
        get: operation({ tag: "Scores", operationId: "getScore", summary: "One round, with its final board", auth: true, parameters: [pathParam("id", { type: "string" }, "Score identifier.")], responses: { "200": response("The round.", { type: "object", properties: { score: ref("Score") } }), "404": errorResponse("No such round on this account.") } }),
        delete: operation({
            tag: "Scores",
            operationId: "deleteScore",
            summary: "Delete a round",
            description: "Career totals are intentionally left alone: they record rounds played, and making `gamesPlayed` go down because a row was removed is not what anyone expects.",
            auth: true,
            parameters: [pathParam("id", { type: "string" }, "Score identifier.")],
            responses: { "200": response("Deleted.", { type: "object", properties: { deleted: { type: "boolean" } } }), "404": errorResponse("No such round on this account.") }
        })
    }
};

const leaderboardPaths = {
    [`${BASE}/leaderboard`]: {
        get: operation({
            tag: "Leaderboard",
            operationId: "getLeaderboard",
            summary: "A ranked page",
            description:
                "One row per player — their best qualifying round in the window, never three of the same player's games in the top ten. Ties break by the earlier submission, so a player's rank does not drift between two identical requests.\n\n" +
                "Authenticated requests mark the viewer's own row with `isViewer` and are never shared-cached.",
            parameters: [...PAGINATION_PARAMS, PERIOD_PARAM, MODE_PARAM, query("challengeDate", { type: "string" }, "For `mode=daily`, the challenge date.")],
            responses: { "200": response("A page of the board.", ref("LeaderboardPage")) }
        })
    },
    [`${BASE}/leaderboard/periods`]: {
        get: operation({ tag: "Leaderboard", operationId: "getLeaderboardPeriods", summary: "The exact UTC boundaries of every window", responses: { "200": response("Window boundaries.", { type: "object", additionalProperties: true }) } })
    },
    [`${BASE}/leaderboard/me`]: {
        get: operation({ tag: "Leaderboard", operationId: "getMyRank", summary: "The signed-in player's rank", auth: true, parameters: [PERIOD_PARAM, MODE_PARAM], responses: { "200": response("Rank and percentile.", ref("Rank")) } })
    },
    [`${BASE}/leaderboard/around-me`]: {
        get: operation({
            tag: "Leaderboard",
            operationId: "getRanksAroundMe",
            summary: "The slice of the board around the player",
            auth: true,
            parameters: [PERIOD_PARAM, MODE_PARAM, query("radius", { type: "integer", minimum: 1, maximum: 25, default: 4 }, "Rows either side.")],
            responses: { "200": response("Neighbouring ranks.", { type: "object", additionalProperties: true }) }
        })
    },
    [`${BASE}/leaderboard/friends`]: {
        get: operation({ tag: "Leaderboard", operationId: "getFriendsLeaderboard", summary: "A board of the people the player follows", auth: true, parameters: [...PAGINATION_PARAMS, PERIOD_PARAM], responses: { "200": response("A page of the board.", ref("LeaderboardPage")) } })
    },
    [`${BASE}/leaderboard/users/{username}`]: {
        get: operation({ tag: "Leaderboard", operationId: "getPlayerRank", summary: "Any player's rank", parameters: [pathParam("username", { type: "string" }, "Case-insensitive username."), PERIOD_PARAM, MODE_PARAM], responses: { "200": response("Rank and percentile.", ref("Rank")), "404": errorResponse("No such player.") } })
    }
};

const achievementPaths = {
    [`${BASE}/achievements`]: {
        get: operation({ tag: "Achievements", operationId: "listAchievements", summary: "The catalog", description: "Definitions are compiled into the build, so this changes only on deploy and is cached for an hour.", responses: { "200": response("Every achievement.", { type: "object", properties: { items: { type: "array", items: ref("Achievement") } } }) } })
    },
    [`${BASE}/achievements/me`]: {
        get: operation({ tag: "Achievements", operationId: "getMyAchievements", summary: "Progress for the signed-in player", auth: true, responses: { "200": response("Every achievement, earned or not, plus a completion summary.", { type: "object", properties: { items: { type: "array", items: ref("Achievement") }, summary: { type: "object", additionalProperties: true } } }) } })
    },
    [`${BASE}/achievements/{key}`]: {
        get: operation({ tag: "Achievements", operationId: "getAchievement", summary: "One definition", parameters: [pathParam("key", { type: "string" }, "Achievement key, for example `tile_2048`.")], responses: { "200": response("The definition.", { type: "object", properties: { achievement: ref("Achievement") } }), "404": errorResponse("No such achievement.") } })
    }
};

const statsPaths = {
    [`${BASE}/stats/global`]: {
        get: operation({ tag: "Statistics", operationId: "getGlobalStats", summary: "Service-wide totals", responses: { "200": response("Totals.", ref("GlobalStats")) } })
    },
    [`${BASE}/stats/tiles`]: {
        get: operation({ tag: "Statistics", operationId: "getTileDistribution", summary: "How far rounds get", description: "The share of rounds ending at each highest tile — the clearest single picture of the difficulty curve.", responses: { "200": response("Distribution.", { type: "object", additionalProperties: true }) } })
    },
    [`${BASE}/stats/activity`]: {
        get: operation({ tag: "Statistics", operationId: "getActivitySeries", summary: "A dense daily series", description: "Days with no games appear as zeroes rather than being omitted, so the series can be charted without silently rewriting the x-axis.", parameters: [query("days", { type: "integer", minimum: 1, maximum: 365, default: 30 }, "Length of the window.")], responses: { "200": response("The series.", { type: "object", additionalProperties: true }) } })
    },
    [`${BASE}/stats/me`]: {
        get: operation({ tag: "Statistics", operationId: "getMyStats", summary: "The signed-in player's statistics", auth: true, responses: { "200": response("Statistics.", ref("PersonalStats")) } })
    },
    [`${BASE}/stats/me/activity`]: {
        get: operation({ tag: "Statistics", operationId: "getMyActivity", summary: "The signed-in player's daily series", auth: true, parameters: [query("days", { type: "integer", minimum: 1, maximum: 365, default: 30 }, "Length of the window.")], responses: { "200": response("The series.", { type: "object", additionalProperties: true }) } })
    }
};

const socialPaths = {
    [`${BASE}/social/follow/{username}`]: {
        post: operation({ tag: "Social", operationId: "followPlayer", summary: "Follow a player", description: "Idempotent: following twice succeeds rather than returning a duplicate-key error the client has to special-case.", auth: true, parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")], responses: { "201": response("Now following.", { type: "object", additionalProperties: true }), "200": response("Already following.", { type: "object", additionalProperties: true }), "400": errorResponse("You cannot follow yourself.") } }),
        delete: operation({ tag: "Social", operationId: "unfollowPlayer", summary: "Unfollow a player", auth: true, parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")], responses: { "200": response("No longer following.", { type: "object", additionalProperties: true }) } })
    },
    [`${BASE}/social/following`]: {
        get: operation({ tag: "Social", operationId: "listFollowing", summary: "Who the player follows", auth: true, parameters: PAGINATION_PARAMS, responses: { "200": response("Players.", { type: "object", properties: { items: { type: "array", items: ref("PublicUser") }, pagination: ref("Pagination") } }) } })
    },
    [`${BASE}/social/followers`]: {
        get: operation({ tag: "Social", operationId: "listFollowers", summary: "Who follows the player", auth: true, parameters: PAGINATION_PARAMS, responses: { "200": response("Players.", { type: "object", properties: { items: { type: "array", items: ref("PublicUser") }, pagination: ref("Pagination") } }) } })
    },
    [`${BASE}/social/relationship/{username}`]: {
        get: operation({ tag: "Social", operationId: "getRelationship", summary: "The edge between two players", auth: true, parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")], responses: { "200": response("Both directions.", { type: "object", additionalProperties: true }) } })
    },
    [`${BASE}/social/suggestions`]: {
        get: operation({ tag: "Social", operationId: "getFollowSuggestions", summary: "Players worth following", description: "Strong players the viewer does not already follow. The heuristic is deliberately that simple.", auth: true, parameters: [query("limit", { type: "integer", minimum: 1, maximum: 25, default: 10 }, "How many.")], responses: { "200": response("Suggestions.", { type: "object", properties: { items: { type: "array", items: ref("PublicUser") } } }) } })
    }
};

const challengePaths = {
    [`${BASE}/challenges/daily`]: {
        get: operation({
            tag: "Daily challenge",
            operationId: "getDailyChallenge",
            summary: "Today's challenge",
            description: "The board is *derived* from the date with a seeded generator, not stored, so every client gets the same opening position and can reproduce it offline from the seed alone.",
            responses: { "200": response("The challenge.", { type: "object", properties: { challenge: ref("DailyChallenge"), attempted: { type: "boolean" } } }) }
        })
    },
    [`${BASE}/challenges/daily/leaderboard`]: {
        get: operation({ tag: "Daily challenge", operationId: "getDailyLeaderboard", summary: "The board for one day", parameters: [...PAGINATION_PARAMS, query("date", { type: "string", example: "2026-09-18" }, "Defaults to today (UTC).")], responses: { "200": response("A page of the board.", { type: "object", additionalProperties: true }) } })
    },
    [`${BASE}/challenges/daily/me`]: {
        get: operation({ tag: "Daily challenge", operationId: "getMyDailyRank", summary: "The player's rank in a day's challenge", auth: true, parameters: [query("date", { type: "string" }, "Defaults to today (UTC).")], responses: { "200": response("Rank and percentile.", ref("Rank")) } })
    },
    [`${BASE}/challenges/daily/submit`]: {
        post: operation({
            tag: "Daily challenge",
            operationId: "submitDailyScore",
            summary: "Submit today's attempt",
            description: "Only today's challenge accepts submissions. Without that rule the daily board becomes a backlog anyone can grind through.",
            auth: true,
            requestBody: body({
                type: "object",
                required: ["score"],
                properties: { date: { type: "string" }, board: ref("Board"), grid: ref("Board"), score: { type: "integer", minimum: 0 }, moves: { type: "integer", minimum: 0 }, durationSeconds: { type: "integer", minimum: 0 }, client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] } }
            }),
            responses: { "201": response("Recorded.", { type: "object", additionalProperties: true }), "200": response("Already recorded.", { type: "object", additionalProperties: true }), "400": errorResponse("The date is invalid or is not today.") }
        })
    },
    [`${BASE}/challenges/daily/{date}`]: {
        get: operation({ tag: "Daily challenge", operationId: "getChallengeForDate", summary: "Any day's challenge", parameters: [pathParam("date", { type: "string", example: "2026-09-18" }, "ISO date.")], responses: { "200": response("The challenge.", { type: "object", properties: { challenge: ref("DailyChallenge") } }), "400": errorResponse("Not a valid calendar date.") } })
    }
};

const eventPaths = {
    [`${BASE}/events`]: {
        post: operation({
            tag: "Telemetry",
            operationId: "recordEvents",
            summary: "Record gameplay events",
            description:
                "Coarse, opt-in, pseudonymous, and closed-vocabulary: both the event types and the metadata keys are enumerated, so this cannot become a general sink or accidentally carry a board. Rows expire after 90 days. See `docs/privacy.md`.",
            requestBody: body({
                type: "object",
                required: ["events"],
                properties: {
                    client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] },
                    anonymousId: { type: "string", maxLength: 64, description: "Ignored for signed-in callers, so the two identities are never linked." },
                    events: { type: "array", minItems: 1, maxItems: config.limits.maxEventsPerBatch, items: { type: "object", additionalProperties: true } }
                }
            }),
            responses: { "202": response("Accepted.", { type: "object", properties: { accepted: { type: "integer" } } }) }
        })
    },
    [`${BASE}/events/summary`]: {
        get: operation({ tag: "Telemetry", operationId: "getEventSummary", summary: "Event counts by type and client", parameters: [query("days", { type: "integer", minimum: 1, maximum: 90, default: 7 }, "Window length.")], responses: { "200": response("Counts.", { type: "object", additionalProperties: true }) } })
    }
};

/* ---------------------------------------------------------------------- */
/* Document                                                                 */
/* ---------------------------------------------------------------------- */

export function buildOpenApiDocument({ serverUrl = config.publicUrl } = {}) {
    return {
        openapi: "3.1.0",
        info: {
            title: "2048 Cloud API",
            version: config.version,
            summary: "Accounts, cross-device saves, leaderboards, achievements, and statistics for the 2048 game.",
            description: [
                "This API is the optional cloud half of [2048](https://hoangsonww.github.io/2048-Game/). The game itself is still entirely local: every client plays, scores, undoes, and saves without ever calling this service, and a player who never signs in never touches it.",
                "",
                "What an account adds is continuity — the same round and the same best score on a laptop, a phone, and a tablet — plus leaderboards, achievements, and a daily challenge.",
                "",
                "The service root (`GET /`) redirects to this documentation at `/docs`. Machine-readable OpenAPI lives at `/openapi.json`; Redoc and Scalar are at `/redoc` and `/reference`.",
                "",
                "### Principles",
                "",
                "- **The game never depends on the network.** Every endpoint here is additive. If this service is down, all three clients keep working exactly as they did before it existed.",
                "- **Rules stay in the clients.** The server validates boards and sanity-checks scores; it never simulates a move. A single-player puzzle has no authoritative server simulation to offer.",
                "- **Nothing is silently discarded.** When two devices disagree about a round, the further one wins and the other is preserved in a conflict slot the player can recover.",
                "- **Deletion means deletion.** `DELETE /auth/me` removes the account and every row that references it, in one request, with no tombstone.",
                "",
                "### Authentication",
                "",
                "Send `Authorization: Bearer <accessToken>`. Access tokens are short-lived and stateless; refresh tokens are long-lived, stored only as a hash, and rotated on every use. Replaying a rotated refresh token revokes the session.",
                "",
                "### Errors",
                "",
                "Every failure is `{ \"error\": { \"code\", \"message\", \"details\"? }, \"requestId\" }`. Branch on `code`, never on `message`. Quote `requestId` in a bug report; it is also returned in the `X-Request-Id` header."
            ].join("\n"),
            contact: { name: "Son Nguyen", url: "https://github.com/hoangsonww/2048-Game" },
            license: { name: "MIT", identifier: "MIT" }
        },
        servers: [
            { url: serverUrl, description: "This deployment" },
            { url: "http://localhost:4000", description: "Local development" }
        ],
        externalDocs: { description: "Repository and architecture notes", url: "https://github.com/hoangsonww/2048-Game/blob/main/docs/backend.md" },
        tags: [
            { name: "Meta", description: "Health, readiness, version, configuration, and counters." },
            { name: "Authentication", description: "Accounts, tokens, sessions, and deletion." },
            { name: "Players", description: "Profiles, preferences, search, and data export." },
            { name: "Cloud saves", description: "Cross-device round synchronisation with conflict preservation." },
            { name: "Scores", description: "Submitting and reading finished rounds." },
            { name: "Leaderboard", description: "Ranked boards over UTC windows." },
            { name: "Achievements", description: "The catalog and a player's progress through it." },
            { name: "Statistics", description: "Aggregates, distributions, and activity series." },
            { name: "Social", description: "Follows, used only to scope a leaderboard." },
            { name: "Daily challenge", description: "A seeded board everyone plays on the same UTC day." },
            { name: "Telemetry", description: "Coarse, opt-in, expiring gameplay events." }
        ],
        components: {
            securitySchemes: {
                bearerAuth: { type: "http", scheme: "bearer", bearerFormat: "JWT", description: "An access token from `/auth/login`, `/auth/register`, or `/auth/refresh`." }
            },
            schemas
        },
        security: [],
        paths: {
            ...metaPaths,
            ...authPaths,
            ...userPaths,
            ...savePaths,
            ...scorePaths,
            ...leaderboardPaths,
            ...achievementPaths,
            ...statsPaths,
            ...socialPaths,
            ...challengePaths,
            ...eventPaths
        }
    };
}

export default buildOpenApiDocument;
