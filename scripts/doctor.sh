#!/usr/bin/env bash

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

status=0
check_tool() {
    local command_name="$1"
    local purpose="$2"
    if command -v "${command_name}" >/dev/null 2>&1; then
        printf 'ok       %-12s %s\n' "${command_name}" "${purpose}"
    else
        printf 'missing  %-12s %s\n' "${command_name}" "${purpose}"
        status=1
    fi
}

printf '2048 development environment\n\n'
check_tool git "source control"
check_tool node "web development (Node 22 recommended)"
check_tool npm "locked JavaScript dependencies"
check_tool java "Android compilation (JDK 17 required)"
check_tool shellcheck "shell-script linting (recommended)"

if [[ "$(uname -s)" == "Darwin" ]]; then
    check_tool xcodebuild "iOS builds and tests"
    check_tool xcrun "iOS simulator control"
else
    printf 'n/a      %-12s %s\n' "Xcode" "iOS requires macOS"
fi

if [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}" ]]; then
    printf 'ok       %-12s %s\n' "ANDROID_HOME" "${ANDROID_HOME}"
else
    printf 'notice   %-12s %s\n' "ANDROID_HOME" "not set; Android Studio may still provide the SDK"
fi

printf '\nRepository: %s\n' "${PROJECT_ROOT}"
exit "${status}"
