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

# Coverage is collected above; report it and hold the app target to a floor so a
# regression fails the run rather than being noticed later.
minimum_coverage="${IOS_MINIMUM_COVERAGE:-90}"
result_bundle="$(find "${derived_data}/Logs/Test" -maxdepth 1 -name '*.xcresult' -print0 2>/dev/null \
    | xargs -0 ls -td 2>/dev/null | head -1 || true)"

if [[ -z "${result_bundle}" ]]; then
    echo "No .xcresult produced; skipping the coverage gate." >&2
    exit 0
fi

echo
echo "Coverage (Game-2048.app):"
xcrun xccov view --report --files-for-target Game-2048.app "${result_bundle}" \
    | awk 'NR>3 && NF { name=$2; sub(/.*\//, "", name); printf "  %-26s %s %s\n", name, $(NF-1), $NF }'

percent="$(xcrun xccov view --report --only-targets "${result_bundle}" \
    | awk '$2 == "Game-2048.app" { gsub(/%/, "", $(NF-1)); print $(NF-1); exit }')"

if [[ -z "${percent}" ]]; then
    echo "Could not read a coverage percentage from ${result_bundle}." >&2
    exit 1
fi

if awk -v value="${percent}" -v floor="${minimum_coverage}" 'BEGIN { exit !(value < floor) }'; then
    echo "Coverage ${percent}% is below the required ${minimum_coverage}%." >&2
    exit 1
fi

echo "Coverage ${percent}% meets the ${minimum_coverage}% floor."
