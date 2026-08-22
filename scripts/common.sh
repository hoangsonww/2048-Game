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
