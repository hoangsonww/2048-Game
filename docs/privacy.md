# Privacy

How 2048 handles data, with and without an account.

## Default: local-only play

With no account, **nothing leaves the device**.

- No sign-in, no user identifiers, no analytics SDK, no advertising SDK, no crash reporter
- The round and best score live in `localStorage` (web), `UserDefaults` (iOS), or `SharedPreferences` (Android)
- Clearing site data or deleting the app removes that state
- The web client may fetch Google Fonts for the display typeface; the game remains playable if that request is blocked

## Optional account

An account is offered under the board as an invitation. Declining it, or dismissing the prompt, leaves play exactly as before.

When someone creates an account, the API stores:

| Data | Purpose |
| --- | --- |
| Username, email, password hash (bcrypt) | Sign-in |
| Display name and public profile fields | Leaderboard / social |
| Cloud save slots (board, score, moves, flags) | Cross-device continuity |
| Submitted scores | Leaderboards |
| Achievement unlocks and aggregate statistics | Account screen |
| Refresh-token hashes and session metadata | Auth rotation |
| Optional coarse event kinds (no board content) | Product questions; TTL 90 days |

The API does **not** store device fingerprints for advertising, payment data, or third-party tracking identifiers.

## Tokens on device

Access and refresh tokens are kept beside the local save:

| Platform | Storage | Why |
| --- | --- | --- |
| Web | `localStorage` | Same trust boundary as the saved round |
| Android | `SharedPreferences` | Matches the existing save store; no EncryptedSharedPreferences migration for a token whose worst case is an unlocked-device read of 2048 scores |
| iOS | `UserDefaults` | Same reasoning; Keychain would add entitlement and failure modes without a commensurate threat model |

Signing out clears tokens locally and best-effort revokes the refresh token on the server. The local round stays on the device.

## Network

- Production API: `https://game-2048-cloud-api.vercel.app`
- Clients send `X-Client: web|android|ios`
- Offline or failed sync never blocks a move; status text explains and the board keeps working
- Server-driven help surfaces (iOS / Android) remain content-only with a native fallback — see [ARCHITECTURE.md](../ARCHITECTURE.md#server-driven-surfaces)

## Deletion

Account deletion (authenticated API) removes the user document and associated saves, scores, achievements, follows, and sessions. Local device state is unchanged until the player clears it themselves.

## Contact

Security reports: see [SECURITY.md](../.github/SECURITY.md).
