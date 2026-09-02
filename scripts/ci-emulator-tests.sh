#!/usr/bin/env bash

# Runs the Compose instrumentation suite against an already-booted emulator,
# retrying once when the *emulator* is at fault rather than the tests.
#
# This exists as a file rather than inline workflow YAML for a specific reason:
# reactivecircus/android-emulator-runner executes its `script:` input one line
# at a time, each in its own `sh -c`. Multi-line shell constructs are split
# across invocations and die with
# "Syntax error: end of file unexpected (expecting \"done\")", and no variable
# survives from one line to the next. A single line invoking this script is the
# way to run anything with control flow.
#
# Usage (from the workflow, as one line):
#   ../../scripts/ci-emulator-tests.sh
#
# Intended for CI. It assumes a device is already attached.

set -Eeuo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

readonly APP_ID="com.sonnguyenhoang.game2048"
readonly MAX_ATTEMPTS=2

# These all mean the device never hosted the app: the activity never launched,
# the emulator console never came up, or the instrumentation could not be
# installed or started. A failing assertion looks nothing like any of them.
readonly UNHEALTHY_PATTERN='No compose hierarchies found|Failed to start Emulator console|INSTALL_FAILED|Test run failed to complete|Unable to find instrumentation|Could not access the Package Manager'

adb="$(resolve_adb)"
use_java_17

section "Waiting for the device to be genuinely ready"
"${adb}" wait-for-device
until [[ "$("${adb}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    sleep 2
done
until [[ "$("${adb}" shell getprop init.svc.bootanim 2>/dev/null | tr -d '\r')" == "stopped" ]]; do
    sleep 2
done
printf 'Device reports boot complete and the boot animation has stopped.\n'

log="$(mktemp)"
trap 'rm -f "${log}"' EXIT

for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    section "Compose instrumentation suite (attempt ${attempt} of ${MAX_ATTEMPTS})"

    status=0
    (cd "${ANDROID_ROOT}" && ./gradlew connectedDebugAndroidTest --stacktrace) >"${log}" 2>&1 || status=$?
    cat "${log}"

    if [[ "${status}" -eq 0 ]]; then
        exit 0
    fi

    # A genuine test failure has to fail on the first attempt. A retry that
    # caught everything would turn a real regression into an intermittent one,
    # which is worse than the flake it is meant to absorb.
    if ! grep -qE "${UNHEALTHY_PATTERN}" "${log}"; then
        printf '\nThe instrumentation failed on its own terms, not the emulator'"'"'s. Not retrying.\n' >&2
        exit "${status}"
    fi

    if [[ "${attempt}" -eq "${MAX_ATTEMPTS}" ]]; then
        printf '\nThe emulator was still unhealthy on attempt %s. Giving up.\n' "${attempt}" >&2
        exit "${status}"
    fi

    printf '\nAn emulator-health signature was found in the log. Clearing app state and retrying.\n' >&2
    "${adb}" shell am force-stop "${APP_ID}" || true
    "${adb}" shell pm clear "${APP_ID}" || true
    sleep 15
done
