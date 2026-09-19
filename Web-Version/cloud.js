// The cloud client for the web app.
//
// Everything that talks to the network lives here, and nothing here touches
// the DOM. That split is the whole point: this file is a pure function of its
// injected dependencies — `fetch`, `storage`, and `now` — so every branch,
// including the failure branches a browser makes hard to reach, is reachable
// from `node --test`. See ARCHITECTURE.md, "Determinism seams".
//
// The game never waits on this module. If the API is slow, unreachable, or
// disabled, the player keeps playing against localStorage exactly as they did
// before an account existed.
(function exposeCloudClient(root, factory) {
    "use strict";
    const cloud = factory();
    if (typeof module === "object" && module.exports) module.exports = cloud;
    if (root) root.Game2048Cloud = cloud;
})(typeof globalThis !== "undefined" ? globalThis : this, () => {
    "use strict";

    const DEFAULT_BASE_URL = "https://game-2048-cloud-api.vercel.app";
    const TOKEN_KEY = "game2048-cloud-tokens-v1";
    const PROMPT_KEY = "game2048-cloud-prompt-v1";
    const DEVICE_KEY = "game2048-cloud-device-v1";

    /** A failure a caller can show to a player. `code` is stable; the message is not. */
    class CloudError extends Error {
        constructor(code, message, status) {
            super(message);
            this.name = "CloudError";
            this.code = code;
            this.status = status ?? 0;
        }
    }

    function readJSON(storage, key) {
        try {
            const raw = storage.getItem(key);
            return raw ? JSON.parse(raw) : null;
        } catch (_) {
            // A hand-edited or truncated entry is discarded rather than
            // crashing the page — the same rule the game applies to a corrupt
            // saved round.
            storage.removeItem(key);
            return null;
        }
    }

    function writeJSON(storage, key, value) {
        try {
            storage.setItem(key, JSON.stringify(value));
        } catch (_) {
            // Private browsing and a full quota both throw here. Losing the
            // token means the player signs in again; it must not break the game.
        }
    }

    /**
     * A device identifier, used only so a conflict can say which device a
     * round came from. It is random, local, and never sent to anything but
     * this API — it is not an advertising identifier and is not used to
     * correlate anything.
     */
    function deviceId(storage, random) {
        let id = null;
        try {
            id = storage.getItem(DEVICE_KEY);
        } catch (_) {
            id = null;
        }
        if (!id) {
            id = `web-${Math.floor(random() * 1e12).toString(36)}`;
            try {
                storage.setItem(DEVICE_KEY, id);
            } catch (_) {
                // Unstorable is fine; the identifier is a convenience.
            }
        }
        return id;
    }

    /**
     * @param {object} [options]
     * @param {string} [options.baseUrl]
     * @param {typeof globalThis.fetch} [options.fetch]
     * @param {Storage} [options.storage]
     * @param {() => number} [options.now]
     * @param {() => number} [options.random]
     */
    function createCloudClient(options = {}) {
        const baseUrl = (options.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
        // `??` would be wrong here: a caller passing `fetch: null` is saying
        // "no network", and falling back to the global would silently
        // reconnect them.
        const doFetch = options.fetch === undefined
            ? (typeof fetch === "function" ? fetch.bind(globalThis) : null)
            : options.fetch;
        const storage = options.storage ?? (typeof localStorage === "object" ? localStorage : null);
        const now = options.now ?? Date.now;
        const random = options.random ?? Math.random;

        if (!storage) throw new CloudError("unsupported", "This browser has no storage available.");

        let tokens = readJSON(storage, TOKEN_KEY);
        let user = null;
        let lastSync = null;
        let lastResolution = null;
        let lastError = null;
        let refreshing = null;
        const listeners = new Set();

        function snapshot() {
            return {
                available: Boolean(doFetch),
                signedIn: Boolean(tokens?.accessToken && user),
                pending: Boolean(tokens?.accessToken && !user),
                user,
                lastSync,
                lastResolution,
                lastError,
                deviceId: deviceId(storage, random)
            };
        }

        function emit() {
            const state = snapshot();
            for (const listener of listeners) listener(state);
        }

        function setTokens(next) {
            tokens = next;
            if (next) writeJSON(storage, TOKEN_KEY, next);
            else storage.removeItem(TOKEN_KEY);
        }

        function clearSession() {
            setTokens(null);
            user = null;
            lastResolution = null;
            emit();
        }

        async function send(path, { method = "GET", body, token } = {}) {
            if (!doFetch) throw new CloudError("offline", "This browser cannot reach the network.");

            let response;
            try {
                response = await doFetch(`${baseUrl}${path}`, {
                    method,
                    headers: {
                        "content-type": "application/json",
                        "x-client": "web",
                        ...(token ? { authorization: `Bearer ${token}` } : {})
                    },
                    ...(body === undefined ? {} : { body: JSON.stringify(body) })
                });
            } catch (_) {
                // A DNS failure, a dropped connection, an offline laptop. The
                // caller decides whether to retry; the game never blocks on it.
                throw new CloudError("network", "Could not reach the 2048 cloud. Your game is still saved on this device.");
            }

            const text = await response.text();
            let payload = null;
            if (text) {
                try {
                    payload = JSON.parse(text);
                } catch (_) {
                    payload = null;
                }
            }

            if (!response.ok) {
                const error = payload?.error;
                throw new CloudError(error?.code ?? "http_error", error?.message ?? `Request failed with status ${response.status}.`, response.status);
            }

            return payload;
        }

        /**
         * Refreshes at most once at a time.
         *
         * Two requests racing a 401 would otherwise each rotate the refresh
         * token, and the second rotation would look like a replay of the first
         * — which the server treats as theft and responds to by revoking the
         * session. Sharing one in-flight promise is what prevents a signed-in
         * player from being signed out by their own parallel requests.
         */
        function refresh() {
            if (refreshing) return refreshing;
            if (!tokens?.refreshToken) return Promise.reject(new CloudError("unauthorized", "You are signed out."));

            refreshing = send("/api/v1/auth/refresh", { method: "POST", body: { refreshToken: tokens.refreshToken } })
                .then(result => {
                    setTokens({ accessToken: result.accessToken, refreshToken: result.refreshToken });
                    user = result.user;
                    return result;
                })
                .catch(error => {
                    clearSession();
                    throw error;
                })
                .finally(() => {
                    refreshing = null;
                });

            return refreshing;
        }

        async function authed(path, init = {}) {
            if (!tokens?.accessToken) throw new CloudError("unauthorized", "Sign in to use this.");

            try {
                return await send(path, { ...init, token: tokens.accessToken });
            } catch (error) {
                if (error.status !== 401) throw error;
                await refresh();
                return send(path, { ...init, token: tokens.accessToken });
            }
        }

        function adoptSession(result) {
            setTokens({ accessToken: result.accessToken, refreshToken: result.refreshToken });
            user = result.user;
            lastError = null;
            emit();
            return user;
        }

        return {
            /* ---------------------------------------------------------- */
            /* State                                                       */
            /* ---------------------------------------------------------- */

            getState: snapshot,
            isSignedIn: () => Boolean(tokens?.accessToken && user),

            subscribe(listener) {
                listeners.add(listener);
                listener(snapshot());
                return () => listeners.delete(listener);
            },

            /** Whether the sign-up prompt has been dismissed on this device. */
            promptDismissed: () => storage.getItem(PROMPT_KEY) === "dismissed",
            dismissPrompt() {
                try {
                    storage.setItem(PROMPT_KEY, "dismissed");
                } catch (_) {
                    // A dismissal that cannot persist reappears next visit.
                    // Mildly annoying; not worth failing for.
                }
            },

            /* ---------------------------------------------------------- */
            /* Session                                                     */
            /* ---------------------------------------------------------- */

            /**
             * Re-establishes a session from stored tokens on page load.
             * Resolves to null rather than throwing when there is nothing to
             * restore, because "not signed in" is the normal case.
             */
            async restore() {
                if (!tokens?.accessToken) return null;
                try {
                    const result = await authed("/api/v1/auth/me");
                    user = result.user;
                    lastError = null;
                    emit();
                    return user;
                } catch (error) {
                    // A network failure must not sign the player out — they may
                    // simply be on a train. Only a rejected token does.
                    if (error.code === "network") {
                        lastError = error.message;
                        emit();
                        return null;
                    }
                    clearSession();
                    return null;
                }
            },

            async register({ username, email, password, displayName }) {
                return adoptSession(
                    await send("/api/v1/auth/register", {
                        method: "POST",
                        body: { username, email, password, displayName, client: "web" }
                    })
                );
            },

            async login({ identifier, password }) {
                return adoptSession(
                    await send("/api/v1/auth/login", { method: "POST", body: { identifier, password, client: "web" } })
                );
            },

            async logout() {
                const refreshToken = tokens?.refreshToken;
                clearSession();
                if (!refreshToken) return;
                try {
                    await send("/api/v1/auth/logout", { method: "POST", body: { refreshToken } });
                } catch (_) {
                    // The local session is already gone, which is what the
                    // player asked for. A failed server-side revoke is worth
                    // retrying silently, never worth an error dialog.
                }
            },

            /* ---------------------------------------------------------- */
            /* Game data                                                   */
            /* ---------------------------------------------------------- */

            /**
             * Two-way sync of the active round.
             *
             * @param {object|null} localSave The board this device is holding.
             * @param {"auto"|"prefer-local"|"prefer-remote"} [strategy]
             */
            async sync(localSave, strategy = "auto") {
                const result = await authed("/api/v1/saves/sync", {
                    method: "POST",
                    body: {
                        slot: "current",
                        strategy,
                        save: localSave
                            ? { ...localSave, client: "web", deviceId: deviceId(storage, random) }
                            : null
                    }
                });

                lastSync = new Date(now()).toISOString();
                lastResolution = result.resolution;
                lastError = null;
                emit();
                return result;
            },

            async submitScore(round) {
                return authed("/api/v1/scores", { method: "POST", body: { ...round, client: "web" } });
            },

            leaderboard({ period = "all", limit = 10, offset = 0 } = {}) {
                const path = `/api/v1/leaderboard?period=${encodeURIComponent(period)}&limit=${limit}&offset=${offset}`;
                // Readable signed out as well as signed in, and richer signed
                // in — so the board is reachable before anyone has an account.
                return tokens?.accessToken ? authed(path) : send(path);
            },

            myRank(period = "all") {
                return authed(`/api/v1/leaderboard/me?period=${encodeURIComponent(period)}`);
            },

            stats() {
                return authed("/api/v1/stats/me");
            },

            achievements() {
                return authed("/api/v1/achievements/me");
            },

            dailyChallenge() {
                return tokens?.accessToken ? authed("/api/v1/challenges/daily") : send("/api/v1/challenges/daily");
            },

            preferences(next) {
                return authed("/api/v1/users/me/preferences", { method: "PUT", body: next });
            },

            async deleteAccount(password) {
                await authed("/api/v1/auth/me", { method: "DELETE", body: { password, confirm: "DELETE" } });
                clearSession();
            }
        };
    }

    return { createCloudClient, CloudError, DEFAULT_BASE_URL, TOKEN_KEY, PROMPT_KEY, DEVICE_KEY };
});
