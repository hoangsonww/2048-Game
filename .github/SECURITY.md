# Security policy

## Supported versions

Security fixes target the latest commit on the default branch. Historical releases and forks are not actively maintained.

## Architecture and data

The web client is a static application hosted on GitHub Pages. The web, iOS, and Android clients have no project-operated backend, authentication system, analytics pipeline, file upload, or payment flow. Game state and the best score remain in browser or device-local storage.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/hoangsonww/2048-Game/security/advisories/new). Include the affected platform and revision, reproduction steps, impact, and a minimal proof of concept when safe. Do not open a public issue for an unpatched vulnerability or include credentials, signing keys, or personal data.

The maintainer will acknowledge actionable reports when available, investigate impact, and coordinate disclosure after a fix. Please allow a reasonable remediation window before publishing details.

## Scope

Useful reports include unsafe state handling, script injection in the web client, exposed credentials or signing material, malicious dependency behavior, and platform permission issues. Generic automated scan output without a reproducible impact may be closed as informational.
