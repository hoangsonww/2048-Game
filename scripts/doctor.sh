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
# A local JDK 17 is a convenience, not a requirement: Gradle provisions its own
# from gradle/gradle-daemon-jvm.properties when none is present.
if use_java_17 2>/dev/null; then
    printf 'ok       %-12s %s\n' "java" "JDK $(java_major_version) at ${JAVA_HOME:-$(command -v java)}"
else
    printf 'optional %-12s %s\n' "java" "no local JDK 17; Gradle will download one on first build"
fi
check_optional_tool shellcheck "shell-script linting"
check_optional_tool docker "dev container builds"

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

if adb_path="$(resolve_adb 2>/dev/null)"; then
    printf 'ok       %-12s %s\n' "adb" "${adb_path}"
else
    printf 'notice   %-12s %s\n' "adb" "not found; needed only to install on a device"
fi

printf '\nRepository: %s\n' "${PROJECT_ROOT}"
exit "${status}"
