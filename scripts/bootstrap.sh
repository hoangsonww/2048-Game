#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=common.sh
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

# A local JDK 17 is preferred but not required: Gradle provisions its own from
# gradle/gradle-daemon-jvm.properties, so a missing JDK must not fail setup.
if ! use_java_17 2>/dev/null; then
    printf 'No local JDK 17 found. Gradle will download one on the first Android build.\n'
fi

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
printf 'This downloads the Gradle distribution, and a JDK 17 if none is present.\n'
(cd "${ANDROID_ROOT}" && ./gradlew --version >/dev/null)

section "Environment ready"
printf 'Run make help for the available project commands.\n'

# The browser suite needs a Chromium download that this script only performs
# with --with-browser. Say so here rather than letting `make test-web` run the
# whole suite and fail on its last step.
if [[ "${with_browser}" == false ]] && ! browser_runtime_installed; then
    printf '\nBrowser tests need a one-time Chromium download:\n'
    printf '  npx playwright install chromium\n'
    printf 'Or re-run this script as: ./scripts/bootstrap.sh --with-browser\n'
fi
