# Security policy

## Supported versions

Security fixes target the latest commit on the default branch. Historical releases and forks are not actively maintained.

## Architecture and data

The web client is a static application hosted on GitHub Pages. Play is local-first on web, iOS, and Android: the active round and best score always live in browser or device-local storage, and a move never requires the network.

An optional Cloud API (`server/`, deployed at [game-2048-cloud-api.vercel.app](https://game-2048-cloud-api.vercel.app); `/` redirects to `/docs`) provides accounts, JWT auth, cross-device save sync, scores, and leaderboards. There is no analytics pipeline, advertising SDK, file upload, or payment flow. See [docs/privacy.md](../docs/privacy.md) and [docs/backend.md](../docs/backend.md).

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/hoangsonww/2048-Game/security/advisories/new). Include the affected platform and revision, reproduction steps, impact, and a minimal proof of concept when safe. Do not open a public issue for an unpatched vulnerability or include credentials, signing keys, or personal data.

The maintainer will acknowledge actionable reports when available, investigate impact, and coordinate disclosure after a fix. Please allow a reasonable remediation window before publishing details.

## Scope

Useful reports include unsafe state handling, script injection in the web client, auth or sync flaws in the Cloud API, exposed credentials or signing material, malicious dependency behavior, and platform permission issues. Generic automated scan output without a reproducible impact may be closed as informational.
