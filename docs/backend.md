# 2048 Cloud API

The optional backend behind accounts, cross-device saves, scores, and leaderboards.

Live deployment: [https://game-2048-cloud-api.vercel.app](https://game-2048-cloud-api.vercel.app)
Reference: [/docs](https://game-2048-cloud-api.vercel.app/docs) · [/redoc](https://game-2048-cloud-api.vercel.app/redoc) · [/reference](https://game-2048-cloud-api.vercel.app/reference) · [/openapi.json](https://game-2048-cloud-api.vercel.app/openapi.json)

The service root (`/`) redirects to Swagger UI at `/docs`.

## Product posture

The game is still **local-first**. Every client plays, scores, undoes, and restores a round with no network. An account is an invitation under the board, never a gate on the board.

| Layer | Responsibility |
| --- | --- |
| Rules engine | Local, unchanged, no knowledge of the cloud |
| Local store | Still the source of truth for the active round |
| Cloud client | Additive: auth, sync, leaderboard — removable without breaking play |
| API | Stores rounds, scores, and account metadata; never ships game rules or UI |

If the API is unreachable, play continues on the device. Sync retries on the next signed-in move or restore.

## Stack

- **Express 5** + **Mongoose 8** against MongoDB Atlas database `game2048`
- **JWT** access + refresh tokens (refresh hashed at rest, rotated on use, race-safe)
- **Zod** request validation, **Helmet** / **CORS** / in-memory rate limits
- **OpenAPI 3.1** built in code, rendered by Swagger UI, Redoc, and Scalar; Postman collection derived from the same document
- Deployed as one **Vercel** serverless function (`server/api/index.js`); local `node src/server.js` for development

## Wire contract (clients)

All three clients speak the same shapes. Boards travel as a flat 16-element row-major array.

```json
{
  "board": [2, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  "score": 40,
  "bestScore": 1200,
  "won": false,
  "gameOver": false,
  "moves": 12,
  "elapsedSeconds": 90,
  "baseRevision": 3,
  "client": "ios",
  "deviceId": "…"
}
```

`moves` measures how far a round has gone. Undo must not decrease it — a number a player can lower by pressing a button is not a progress signal for sync.

### Sync resolution

`POST /api/v1/saves/sync` compares the device save with the stored `current` slot:

| Resolution | Meaning |
| --- | --- |
| `uploaded` | This device's round is now `current` |
| `downloaded` | The server's round replaced the local board |
| `in_sync` | Nothing changed |
| `conflicted` | The further round won; the other was parked in a recoverable conflict slot |

Nothing is silently discarded. Prefer the higher `moves` (then score) when both sides advanced.

### What a client may offer

A sign-in sends `save: null`. A round played before anyone signed in belongs
to the device, not to the account that just signed in on it, so there is
nothing to reconcile: the server either returns the account's own round
(`downloaded`) or has none (`in_sync`, `save: null`) and the clean board the
client just created stands. Clients keep that round in a storage slot of its
own — see [ARCHITECTURE.md](../ARCHITECTURE.md#guest-and-account-profiles) —
and a session's first upload happens on the first move made while signed in.

Career statistics in `GET /api/v1/auth/me` are computed by the server from
submitted rounds. Clients render them verbatim and never merge a local best
score or highest tile into them.

## Auth

- Register / login issue an access token (short TTL) and a refresh token (long TTL)
- `POST /auth/reset-password` is an **interim** recovery path: a matching username and email set a new password and revoke every session. Knowing both is therefore account takeover, which is why it is gated behind `FEATURE_PASSWORD_RESET`, sits under the auth rate limiter, and answers identically whichever half is wrong. Replace it with a mailed single-use token before this service holds anything a person would mind losing.
- Refresh rotates: the previous refresh hash is invalidated; concurrent refreshes are serialised on the client so two 401 retries cannot revoke each other
- Access tokens live in memory or local storage per platform; see [privacy.md](privacy.md) for the deliberate Keychain / EncryptedSharedPreferences trade-offs
- `Authorization: Bearer <access>` on protected routes; public leaderboard and health stay open

## Client map

| Client | Cloud module | Bridge into the rules engine |
| --- | --- | --- |
| Web | `Web-Version/cloud.js`, `account.js` | `Game2048Game` exposes `cloudSave` / `applyCloudSave` plus `beginAccountSession` / `endAccountSession` |
| Android | `…/cloud/*` + `CloudController` | `GameViewModel` cloud save / apply plus `beginAccountSession` / `endAccountSession` |
| iOS | `Game-2048/Cloud/*` + `CloudController` | `GameViewModel.cloudSave()` / `applyCloudSave(_:)` plus `beginAccountSession(fresh:)` / `endAccountSession()` |

Authenticating and adopting a round are separate calls on every client.
`register` / `login` return a session and nothing more; the game then switches
profile and asks the controller to adopt the account's round. Only the game
knows which board is on screen, so only the game can decide what may be sent.

Removing the cloud layer is a delete of those modules plus the header / banner wiring. The board and rules stay.

## Screenshots

Canonical captures live under `images/` (`web-cloud-*`, `android-cloud-*`, `ios-cloud-guest.png`). Regenerate the web set with `make screenshots-web`.

## Local development

```bash
cd server
cp .env.example .env   # fill MONGODB_URI, JWT secrets
npm install
npm run dev            # http://localhost:4000
npm test               # unit
npm run test:integration   # requires MONGODB_TEST_URI ending in _test
npm run smoke          # against PUBLIC_URL or the live deploy
```

Environment variables are documented in `server/.env.example`. Never commit `.env`. Production refuses to boot without `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET`.

## Deploy

Deployed with the Vercel CLI (not GitHub integration):

```bash
cd server
vercel --prod
```

Project env vars mirror `.env.example`. The function entry is `api/index.js`; static docs assets live under `public/`.

## Rate limits

In-memory, per-instance. That stops a runaway client loop; it is not a distributed DDoS shield. Documented honestly so a Redis store can replace it later without redesigning callers.

## Feature flags

`FEATURE_REGISTRATION`, `FEATURE_LEADERBOARDS`, `FEATURE_CLOUD_SAVES`, `FEATURE_SOCIAL`, `FEATURE_DAILY_CHALLENGE`, `FEATURE_EVENTS` — a disabled feature answers `503` with `feature_disabled` so surfaces can be retired without redeploying every client.
