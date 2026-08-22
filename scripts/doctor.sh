#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=common.sh
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

check_optional_tool() {
    local command_name="$1"
    local purpose="$2"
    if command -v "${command_name}" >/dev/null 2>&1; then
        printf 'ok       %-12s %s\n' "${command_name}" "${purpose}"
    else
        printf 'optional %-12s %s\n' "${command_name}" "${purpose}"
    fi
}

printf '2048 development environment\n\n'
check_tool git "source control"
check_tool node "web development (Node 22 recommended)"
check_tool npm "locked JavaScript dependencies"
if use_java_17; then
    printf 'ok       %-12s %s\n' "java" "JDK $(java_major_version) at ${JAVA_HOME:-$(command -v java)}"
else
    printf 'missing  %-12s %s\n' "java" "JDK 17 is required for Android"
    status=1
fi
check_optional_tool shellcheck "shell-script linting"

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
