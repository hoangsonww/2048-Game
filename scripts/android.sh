#!/usr/bin/env bash

# Runs Gradle for the Android client with a guaranteed-correct JDK.
#
# Gradle honours JAVA_HOME, and most machines have several JDKs installed with
# JAVA_HOME pointing at whichever one was configured last. The Android Gradle
# plugin refuses to run on anything older than JDK 17, so invoking ./gradlew
# directly fails on a machine whose default JDK is older. This wrapper resolves
# a JDK 17 first, then delegates every argument through to the Gradle wrapper.
#
# Usage:
#   scripts/android.sh assembleDebug
#   scripts/android.sh testDebugUnitTest lintDebug
#   scripts/android.sh --help

set -Eeuo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ANDROID_APP_ID="com.sonnguyenhoang.game2048"

if [[ $# -eq 0 ]]; then
    printf 'Usage: %s <gradle-task> [gradle-task...]\n' "$0" >&2
    printf '       %s run       Install and launch on a connected device\n' "$0" >&2
    printf '       %s devices   List connected devices and emulators\n\n' "$0" >&2
    printf 'Common Gradle tasks:\n' >&2
    printf '  assembleDebug             Build the debug APK\n' >&2
    printf '  installDebug              Build and install on a connected device\n' >&2
    printf '  testDebugUnitTest         Run deterministic ViewModel tests\n' >&2
    printf '  lintDebug                 Run Android lint\n' >&2
    printf '  connectedDebugAndroidTest Run Compose tests on a device\n' >&2
    printf '  tasks                     List every available Gradle task\n' >&2
    exit 2
fi

if [[ "$1" == "devices" ]]; then
    adb="$(resolve_adb)"
    section "Connected Android devices"
    "${adb}" devices -l
    exit 0
fi

if [[ "$1" == "run" ]]; then
    adb="$(resolve_adb)"
    if [[ -z "$("${adb}" devices | awk 'NR>1 && $2 == "device"')" ]]; then
        printf 'No connected device or emulator.\n' >&2
        printf 'Start one from Android Studio, or run:\n' >&2
        printf '  %s/emulator/emulator -list-avds\n' "${ANDROID_HOME:-\$ANDROID_HOME}" >&2
        printf '  %s/emulator/emulator -avd <name> &\n' "${ANDROID_HOME:-\$ANDROID_HOME}" >&2
        exit 1
    fi

    use_java_17
    printf 'Using Java %s from %s\n' "$(java_major_version)" "${JAVA_HOME:-$(command -v java)}"
    (cd "${ANDROID_ROOT}" && ./gradlew installDebug)

    section "Launching ${ANDROID_APP_ID}"
    "${adb}" shell monkey -p "${ANDROID_APP_ID}" -c android.intent.category.LAUNCHER 1 >/dev/null
    printf 'Launched %s on the connected device.\n' "${ANDROID_APP_ID}"
    exit 0
fi

use_java_17
printf 'Using Java %s from %s\n' "$(java_major_version)" "${JAVA_HOME:-$(command -v java)}"
(cd "${ANDROID_ROOT}" && ./gradlew "$@")
