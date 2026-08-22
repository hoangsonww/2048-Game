#!/usr/bin/env bash

# Builds the dev container image and proves the toolchain inside it actually
# works, rather than only proving the Dockerfile parses.
#
# The container covers the web and Android JVM workflows. iOS cannot be
# containerised: Xcode is macOS-only and its licence forbids redistribution,
# so iOS builds always require a macOS host.
#
# Usage:
#   scripts/verify-devcontainer.sh            # toolchain checks only (fast)
#   scripts/verify-devcontainer.sh --build    # also build the Android client

set -Eeuo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

run_build=false
if [[ "${1:-}" == "--build" ]]; then
    run_build=true
elif [[ $# -gt 0 ]]; then
    printf 'Usage: %s [--build]\n' "$0" >&2
    exit 2
fi

require_command docker

IMAGE_TAG="game2048-devcontainer:verify"

section "Building the dev container image"
docker build --platform=linux/amd64 \
    -f "${PROJECT_ROOT}/.devcontainer/Dockerfile" \
    -t "${IMAGE_TAG}" \
    "${PROJECT_ROOT}"

section "Verifying the toolchain inside the container"
docker run --rm --platform=linux/amd64 "${IMAGE_TAG}" bash -lc '
set -e
fail=0
check() {
    if eval "$2" >/dev/null 2>&1; then
        printf "ok       %-14s %s\n" "$1" "$3"
    else
        printf "MISSING  %-14s %s\n" "$1" "$3"
        fail=1
    fi
}
check java        "java -version"            "JDK for Gradle and AGP"
check javac       "javac -version"           "Java compiler"
check make        "make --version"           "project command surface"
check shellcheck  "shellcheck --version"     "shell linting (required by CI)"
check unzip       "unzip -v"                 "Android SDK extraction"
check curl        "curl --version"           "downloads"
check adb         "adb --version"            "device control"
check sdk-platform "test -d $ANDROID_HOME/platforms/android-34"    "Android SDK 34"
check build-tools  "test -d $ANDROID_HOME/build-tools/34.0.0"      "build-tools 34.0.0"
printf "\njava:  %s\n" "$(java -version 2>&1 | head -1)"
printf "ANDROID_HOME=%s\n" "$ANDROID_HOME"
exit $fail
'

if [[ "${run_build}" == true ]]; then
    section "Building the Android client inside the container"
    printf 'Using an isolated copy so the host build directory is not shared.\n'

    workdir="$(mktemp -d)"
    trap 'rm -rf "${workdir}"' EXIT
    git -C "${PROJECT_ROOT}" archive --format=tar HEAD | tar -x -C "${workdir}"

    docker run --rm --platform=linux/amd64 -v "${workdir}:/work" -w /work "${IMAGE_TAG}" bash -lc '
        cd Android-Version/Game2048 && ./gradlew assembleDebug testDebugUnitTest --no-daemon
        ls -lh app/build/outputs/apk/debug/*.apk
    '
fi

section "Dev container verified"
printf 'Covered: web tooling and the Android JVM workflow.\n'
printf 'Not covered: iOS, which requires Xcode on a macOS host.\n'
