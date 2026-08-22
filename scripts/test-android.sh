#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

device_tests=false
if [[ "${1:-}" == "--device" ]]; then
    device_tests=true
elif [[ $# -gt 0 ]]; then
    printf 'Usage: %s [--device]\n' "$0" >&2
    exit 2
fi

use_java_17
section "Android unit tests, lint, and debug APK"
printf 'Using Java %s from %s\n' "$(java_major_version)" "${JAVA_HOME:-$(command -v java)}"
(cd "${ANDROID_ROOT}" && ./gradlew testDebugUnitTest lintDebug assembleDebug --stacktrace)

if [[ "${device_tests}" == true ]]; then
    section "Android connected-device UI tests"
    (cd "${ANDROID_ROOT}" && ./gradlew connectedDebugAndroidTest --stacktrace)
fi
