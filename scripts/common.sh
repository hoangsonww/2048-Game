#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_ROOT="${PROJECT_ROOT}/Android-Version/Game2048"
export PROJECT_ROOT ANDROID_ROOT

section() {
    printf '\n==> %s\n' "$1"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$1" >&2
        return 1
    fi
}

java_major_version() {
    java -version 2>&1 | awk -F '"' '/version/ { split($2, parts, "."); print (parts[1] == "1" ? parts[2] : parts[1]); exit }'
}

# Echoes a usable adb path. Falls back to the Android SDK location when adb is
# not on PATH, which is the default state after an Android Studio install.
resolve_adb() {
    if command -v adb >/dev/null 2>&1; then
        command -v adb
        return 0
    fi

    local sdk_root candidate
    for sdk_root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "${HOME}/Library/Android/sdk" "${HOME}/Android/Sdk"; do
        [[ -n "${sdk_root}" ]] || continue
        candidate="${sdk_root}/platform-tools/adb"
        if [[ -x "${candidate}" ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
    done

    printf 'adb was not found. Install Android platform-tools or set ANDROID_HOME.\n' >&2
    return 1
}

# True when a Playwright browser has been downloaded. The browser suite needs
# this; `npm ci` alone does not provide it.
browser_runtime_installed() {
    local cache="${PLAYWRIGHT_BROWSERS_PATH:-${HOME}/Library/Caches/ms-playwright}"
    [[ "$(uname -s)" == "Darwin" ]] || cache="${PLAYWRIGHT_BROWSERS_PATH:-${HOME}/.cache/ms-playwright}"
    compgen -G "${cache}/chromium*" >/dev/null 2>&1
}

require_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        printf 'This workflow requires macOS and Xcode.\n' >&2
        return 2
    fi
}

# Echoes the UDID of an available iPhone simulator. Honours IOS_SIMULATOR_ID
# when set, so callers can pin a specific device.
resolve_ios_simulator() {
    local device_id="${IOS_SIMULATOR_ID:-}"

    if [[ -z "${device_id}" ]]; then
        device_id="$(xcrun simctl list devices available -j | node -e '
            let input = "";
            process.stdin.on("data", chunk => input += chunk);
            process.stdin.on("end", () => {
                const devices = Object.values(JSON.parse(input).devices).flat();
                const device = devices.find(item => item.name.startsWith("iPhone"));
                if (device) process.stdout.write(device.udid);
            });
        ')"
    fi

    if [[ -z "${device_id}" ]]; then
        printf 'No available iPhone simulator was found.\n' >&2
        return 1
    fi

    printf '%s' "${device_id}"
}

boot_ios_simulator() {
    local device_id="$1"
    xcrun simctl boot "${device_id}" 2>/dev/null || true
    xcrun simctl bootstatus "${device_id}" -b
}

use_java_17() {
    local candidate=""
    if command -v java >/dev/null 2>&1 && [[ "$(java_major_version)" == "17" ]]; then
        return 0
    fi

    if [[ -n "${JAVA_17_HOME:-}" && -x "${JAVA_17_HOME}/bin/java" ]]; then
        candidate="${JAVA_17_HOME}"
    elif [[ "$(uname -s)" == "Darwin" ]] && [[ -x /usr/libexec/java_home ]]; then
        candidate="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
    elif [[ -x /usr/lib/jvm/java-17-openjdk-amd64/bin/java ]]; then
        candidate="/usr/lib/jvm/java-17-openjdk-amd64"
    fi

    if [[ -n "${candidate}" ]]; then
        export JAVA_HOME="${candidate}"
        export PATH="${JAVA_HOME}/bin:${PATH}"
    fi

    if ! command -v java >/dev/null 2>&1 || [[ "$(java_major_version)" != "17" ]]; then
        printf 'JDK 17 is required. Set JAVA_17_HOME or JAVA_HOME to a JDK 17 installation.\n' >&2
        return 1
    fi
}
