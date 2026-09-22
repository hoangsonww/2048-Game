/**
 * Reusable OpenAPI component schemas.
 *
 * They are written by hand rather than generated from the Zod schemas. A
 * generator would keep them mechanically in step but would also produce the
 * shape of the *input* only, and would strip every example and description —
 * which is most of what makes a reference page usable. The contract test in
 * `tests/unit/openapi.test.js` is what keeps these honest: it asserts that
 * every route the app actually mounts has a documented operation.
 */
export const schemas = {
    Error: {
        type: "object",
        required: ["error"],
        properties: {
            error: {
                type: "object",
                required: ["code", "message"],
                properties: {
                    code: { type: "string", example: "not_found", description: "Stable machine-readable identifier. Branch on this, never on the message." },
                    message: { type: "string", example: "Score was not found." },
                    details: { type: "object", additionalProperties: true }
                }
            },
            requestId: { type: "string", format: "uuid", description: "Echoed in the `X-Request-Id` response header. Quote it in a bug report." }
        }
    },

    Pagination: {
        type: "object",
        properties: {
            total: { type: "integer", example: 412 },
            limit: { type: "integer", example: 25 },
            offset: { type: "integer", example: 0 },
            count: { type: "integer", example: 25 },
            hasMore: { type: "boolean", example: true }
        }
    },

    Board: {
        description: "A board, either as 16 flat cells (row-major) or as a 4x4 grid. Every value is zero or a power of two.",
        oneOf: [
            { type: "array", items: { type: "integer", minimum: 0 }, minItems: 16, maxItems: 16 },
            { type: "array", items: { type: "array", items: { type: "integer", minimum: 0 }, minItems: 4, maxItems: 4 }, minItems: 4, maxItems: 4 }
        ],
        example: [2, 4, 0, 0, 0, 8, 0, 0, 0, 0, 16, 0, 0, 0, 0, 2]
    },

    Preferences: {
        type: "object",
        properties: {
            theme: { type: "string", enum: ["system", "light", "dark"] },
            reducedMotion: { type: "boolean" },
            soundEnabled: { type: "boolean" },
            hapticsEnabled: { type: "boolean" },
            autoSync: { type: "boolean", description: "Whether the client should sync automatically after each valid move." },
            publicProfile: { type: "boolean" },
            showOnLeaderboard: { type: "boolean", description: "Turning this off hides the player's rows without deleting them." }
        }
    },

    Statistics: {
        type: "object",
        properties: {
            bestScore: { type: "integer", example: 24_680 },
            totalScore: { type: "integer", example: 812_400 },
            gamesPlayed: { type: "integer", example: 137 },
            gamesWon: { type: "integer", example: 6 },
            totalMoves: { type: "integer", example: 41_205 },
            highestTile: { type: "integer", example: 4096 },
            totalPlaytimeSeconds: { type: "integer", example: 92_400 },
            lastPlayedAt: { type: "string", format: "date-time", nullable: true }
        }
    },

    PublicUser: {
        type: "object",
        properties: {
            id: { type: "string", example: "66b2f0c0a1c4de00126ab9f1" },
            username: { type: "string", example: "ada" },
            displayName: { type: "string", example: "Ada L." },
            country: { type: "string", nullable: true, example: "GB" },
            avatarColor: { type: "string", example: "#e96345" },
            bio: { type: "string" },
            statistics: { $ref: "#/components/schemas/Statistics" },
            followerCount: { type: "integer" },
            followingCount: { type: "integer" },
            createdAt: { type: "string", format: "date-time" }
        }
    },

    PrivateUser: {
        allOf: [
            { $ref: "#/components/schemas/PublicUser" },
            {
                type: "object",
                properties: {
                    email: { type: "string", format: "email" },
                    roles: { type: "array", items: { type: "string", enum: ["player", "moderator", "admin"] } },
                    preferences: { $ref: "#/components/schemas/Preferences" },
                    emailVerified: { type: "boolean" },
                    lastSeenAt: { type: "string", format: "date-time" },
                    updatedAt: { type: "string", format: "date-time" }
                }
            }
        ]
    },

    TokenPair: {
        type: "object",
        properties: {
            accessToken: { type: "string", description: "Short-lived bearer token. Send as `Authorization: Bearer <token>`." },
            refreshToken: { type: "string", description: "Long-lived, single-use. Every refresh rotates it; replaying an old one revokes the session." },
            tokenType: { type: "string", example: "Bearer" },
            expiresIn: { type: "integer", example: 3600, description: "Access token lifetime in seconds." },
            refreshExpiresIn: { type: "integer", example: 5_184_000 },
            sessionId: { type: "string", format: "uuid" }
        }
    },

    AuthResponse: {
        allOf: [
            { type: "object", properties: { user: { $ref: "#/components/schemas/PrivateUser" } } },
            { $ref: "#/components/schemas/TokenPair" }
        ]
    },

    Session: {
        type: "object",
        properties: {
            id: { type: "string", format: "uuid" },
            client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] },
            userAgent: { type: "string" },
            createdAt: { type: "string", format: "date-time" },
            lastUsedAt: { type: "string", format: "date-time" },
            expiresAt: { type: "string", format: "date-time" },
            revoked: { type: "boolean" },
            current: { type: "boolean", description: "True for the session that made this request." }
        }
    },

    GameSave: {
        type: "object",
        properties: {
            slot: { type: "string", example: "current" },
            label: { type: "string" },
            board: { type: "array", items: { type: "integer" }, minItems: 16, maxItems: 16 },
            grid: { type: "array", items: { type: "array", items: { type: "integer" } }, description: "The same board as 4x4 rows, for clients that store it that way." },
            score: { type: "integer" },
            bestScore: { type: "integer" },
            won: { type: "boolean" },
            gameOver: { type: "boolean" },
            moves: { type: "integer" },
            highestTile: { type: "integer" },
            elapsedSeconds: { type: "integer" },
            undo: {
                type: "object",
                nullable: true,
                description: "The one-step undo snapshot, carried so a device handoff mid-round does not consume the player's undo.",
                properties: { board: { type: "array", items: { type: "integer" } }, score: { type: "integer" }, won: { type: "boolean" } }
            },
            revision: { type: "integer", description: "Increments on every write. Send it back as `baseRevision` to prove a save is a continuation rather than a divergence." },
            client: { type: "string" },
            deviceId: { type: "string" },
            createdAt: { type: "string", format: "date-time" },
            updatedAt: { type: "string", format: "date-time" }
        }
    },

    SavePayload: {
        type: "object",
        required: ["score"],
        properties: {
            board: { $ref: "#/components/schemas/Board" },
            grid: { $ref: "#/components/schemas/Board" },
            score: { type: "integer", minimum: 0 },
            bestScore: { type: "integer", minimum: 0 },
            won: { type: "boolean" },
            gameOver: { type: "boolean" },
            moves: { type: "integer", minimum: 0 },
            elapsedSeconds: { type: "integer", minimum: 0 },
            label: { type: "string", maxLength: 60 },
            deviceId: { type: "string", maxLength: 64 },
            client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] },
            baseRevision: { type: "integer", minimum: 0, description: "The `revision` this device last saw." },
            undo: {
                type: "object",
                nullable: true,
                properties: { board: { $ref: "#/components/schemas/Board" }, score: { type: "integer" }, won: { type: "boolean" } }
            }
        }
    },

    SyncResult: {
        type: "object",
        properties: {
            resolution: {
                type: "string",
                enum: ["uploaded", "downloaded", "in_sync", "conflicted"],
                description: "`conflicted` means both sides had real progress. The further round wins and the other is preserved in `conflictSlot` — nothing is ever discarded."
            },
            winner: { type: "string", nullable: true, enum: ["local", "remote", null] },
            conflictSlot: { type: "string", nullable: true, example: "conflict-m8s2k1" },
            save: { $ref: "#/components/schemas/GameSave" }
        }
    },

    Score: {
        type: "object",
        properties: {
            id: { type: "string" },
            username: { type: "string" },
            displayName: { type: "string" },
            country: { type: "string", nullable: true },
            avatarColor: { type: "string" },
            score: { type: "integer" },
            highestTile: { type: "integer" },
            moves: { type: "integer" },
            durationSeconds: { type: "integer" },
            won: { type: "boolean" },
            gameOver: { type: "boolean" },
            mode: { type: "string", enum: ["classic", "daily"] },
            challengeDate: { type: "string", nullable: true },
            client: { type: "string" },
            verified: {
                type: "boolean",
                description: "False when the score exceeds what its final board could have produced. Unverified rounds are kept but never ranked."
            },
            createdAt: { type: "string", format: "date-time" }
        }
    },

    LeaderboardEntry: {
        type: "object",
        properties: {
            rank: { type: "integer", example: 1 },
            userId: { type: "string" },
            username: { type: "string" },
            displayName: { type: "string" },
            country: { type: "string", nullable: true },
            avatarColor: { type: "string" },
            score: { type: "integer" },
            highestTile: { type: "integer" },
            moves: { type: "integer" },
            durationSeconds: { type: "integer" },
            won: { type: "boolean" },
            client: { type: "string" },
            entries: { type: "integer", description: "How many qualifying rounds this player has in the window." },
            achievedAt: { type: "string", format: "date-time" },
            isViewer: { type: "boolean", description: "Present when the request is authenticated." }
        }
    },

    LeaderboardPage: {
        type: "object",
        properties: {
            entries: { type: "array", items: { $ref: "#/components/schemas/LeaderboardEntry" } },
            summary: {
                type: "object",
                properties: {
                    players: { type: "integer" },
                    topScore: { type: "integer" },
                    averageScore: { type: "integer" },
                    winners: { type: "integer" }
                }
            },
            window: {
                type: "object",
                properties: {
                    period: { type: "string", enum: ["daily", "weekly", "monthly", "yearly", "all"] },
                    since: { type: "string", format: "date-time", nullable: true },
                    until: { type: "string", format: "date-time", nullable: true }
                }
            },
            pagination: { $ref: "#/components/schemas/Pagination" }
        }
    },

    Rank: {
        type: "object",
        properties: {
            ranked: { type: "boolean", description: "False when the player has no qualifying round in the window." },
            rank: { type: "integer", nullable: true },
            players: { type: "integer" },
            percentile: { type: "number", nullable: true, example: 97.4 },
            entry: { $ref: "#/components/schemas/LeaderboardEntry" },
            window: { type: "object", additionalProperties: true }
        }
    },

    Achievement: {
        type: "object",
        properties: {
            key: { type: "string", example: "tile_2048" },
            name: { type: "string", example: "2048" },
            description: { type: "string" },
            category: { type: "string", enum: ["milestone", "tiles", "score", "dedication", "skill", "daily"] },
            points: { type: "integer" },
            progress: { type: "integer" },
            target: { type: "integer" },
            unlocked: { type: "boolean" },
            unlockedAt: { type: "string", format: "date-time", nullable: true }
        }
    },

    DailyChallenge: {
        type: "object",
        properties: {
            date: { type: "string", example: "2026-09-18" },
            dayNumber: { type: "integer", example: 992 },
            seed: { type: "integer", description: "FNV-1a of the date. A client can reproduce the board offline from this alone." },
            board: { type: "array", items: { type: "integer" }, minItems: 16, maxItems: 16 },
            modifier: {
                type: "object",
                properties: {
                    key: { type: "string", enum: ["classic", "tile_hunt", "efficiency", "endurance"] },
                    name: { type: "string" },
                    description: { type: "string" },
                    targetScore: { type: "integer" }
                }
            },
            expiresAt: { type: "string", format: "date-time" }
        }
    },

    GlobalStats: {
        type: "object",
        properties: {
            players: { type: "integer" },
            activeToday: { type: "integer" },
            games: { type: "integer" },
            gamesToday: { type: "integer" },
            savedRounds: { type: "integer" },
            wins: { type: "integer" },
            winRate: { type: "number" },
            topScore: { type: "integer" },
            averageScore: { type: "integer" },
            totalScore: { type: "integer" },
            totalMoves: { type: "integer" },
            highestTile: { type: "integer" },
            generatedAt: { type: "string", format: "date-time" }
        }
    },

    PersonalStats: {
        type: "object",
        properties: {
            games: { type: "integer" },
            wins: { type: "integer" },
            winRate: { type: "number" },
            bestScore: { type: "integer" },
            averageScore: { type: "integer" },
            totalScore: { type: "integer" },
            totalMoves: { type: "integer" },
            totalPlaytimeSeconds: { type: "integer" },
            highestTile: { type: "integer" },
            averageMovesPerGame: { type: "integer" },
            pointsPerMove: { type: "number" },
            firstGameAt: { type: "string", format: "date-time", nullable: true },
            lastGameAt: { type: "string", format: "date-time", nullable: true },
            tiles: {
                type: "object",
                properties: {
                    games: { type: "integer" },
                    buckets: {
                        type: "array",
                        items: {
                            type: "object",
                            properties: { tile: { type: "integer" }, games: { type: "integer" }, bestScore: { type: "integer" }, share: { type: "number" } }
                        }
                    }
                }
            },
            activity: {
                type: "object",
                properties: {
                    days: { type: "integer" },
                    since: { type: "string", format: "date-time" },
                    series: {
                        type: "array",
                        description: "Dense: days with no games appear as zeroes rather than being omitted.",
                        items: {
                            type: "object",
                            properties: { date: { type: "string" }, games: { type: "integer" }, bestScore: { type: "integer" }, totalScore: { type: "integer" }, wins: { type: "integer" } }
                        }
                    }
                }
            },
            recentGames: { type: "array", items: { $ref: "#/components/schemas/Score" } }
        }
    }
};

export default schemas;
