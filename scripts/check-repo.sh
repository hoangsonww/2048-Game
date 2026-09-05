#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ "${1:-}" == "--staged" ]]; then
    section "Checking staged patch whitespace"
    (cd "${PROJECT_ROOT}" && git diff --cached --check)
elif [[ $# -gt 0 ]]; then
    printf 'Usage: %s [--staged]\n' "$0" >&2
    exit 2
fi

section "Checking JavaScript syntax"
(cd "${PROJECT_ROOT}" && npm run check:syntax)

section "Validating repository structure and web discovery metadata"
(cd "${PROJECT_ROOT}" && node scripts/validate-repository.mjs)

# VERSION is the only place a human edits the version; package.json, the Android
# manifest, and the Xcode project are derived from it. CI runs this too, so a
# release cannot be cut from a tree that disagrees with itself.
"${PROJECT_ROOT}/scripts/version.sh" check

if command -v shellcheck >/dev/null 2>&1; then
    section "Checking shell scripts"
    (cd "${PROJECT_ROOT}" && shellcheck -x -P scripts scripts/*.sh .husky/pre-commit .husky/pre-push)
else
    printf '\nNote: shellcheck is unavailable; shell validation was skipped.\n'
fi
