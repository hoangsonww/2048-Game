#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_macos
require_command xcodebuild
require_command xcrun
require_command node

device_id="$(resolve_ios_simulator)"
boot_ios_simulator "${device_id}"

derived_data="${TMPDIR:-/tmp}/Game2048Derived"
(cd "${PROJECT_ROOT}" && xcodebuild \
    -project "2048 Game.xcodeproj" \
    -scheme "Game-2048" \
    -destination "platform=iOS Simulator,id=${device_id}" \
    -derivedDataPath "${derived_data}" \
    test \
    -parallel-testing-enabled NO \
    -enableCodeCoverage YES \
    CODE_SIGNING_ALLOWED=NO)
