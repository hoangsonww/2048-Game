#!/usr/bin/env bash

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

with_browser=false
skip_hooks=false
for argument in "$@"; do
    case "${argument}" in
        --with-browser) with_browser=true ;;
        --skip-hooks) skip_hooks=true ;;
        *) printf 'Unknown option: %s\n' "${argument}" >&2; exit 2 ;;
    esac
done

require_command node
require_command npm
require_command java

section "Installing locked JavaScript dependencies"
if [[ "${skip_hooks}" == true ]]; then
    (cd "${PROJECT_ROOT}" && HUSKY=0 npm ci)
else
    (cd "${PROJECT_ROOT}" && npm ci)
fi

if [[ "${with_browser}" == true ]]; then
    section "Installing the Playwright Chromium runtime"
    (cd "${PROJECT_ROOT}" && npx playwright install chromium)
fi

section "Warming the Gradle wrapper"
(cd "${ANDROID_ROOT}" && ./gradlew --version >/dev/null)

section "Environment ready"
printf 'Run make help for the available project commands.\n'
