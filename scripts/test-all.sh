#!/usr/bin/env bash

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

"${PROJECT_ROOT}/scripts/test-web.sh"
"${PROJECT_ROOT}/scripts/test-android.sh"

if [[ "$(uname -s)" == "Darwin" ]] && command -v xcodebuild >/dev/null 2>&1; then
    "${PROJECT_ROOT}/scripts/test-ios.sh"
else
    section "Skipping iOS tests because Xcode is unavailable on this host"
fi
