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
    -skip-testing:Game-2048UITests/ScreenshotTests \
    CODE_SIGNING_ALLOWED=NO)

# `ScreenshotTests` is skipped on purpose: it drives the simulator to capture
# `images/ios-*.png` and asserts nothing about behaviour, so a capture run must
# never gate a merge. See `scripts/capture-mobile-screenshots.sh`.
#
# Coverage is collected above; report it and hold the app target to a floor so a
# regression fails the run rather than being noticed later.
#
# CloudViews.swift is excluded from the gate the same way Android excludes
# CloudUi.kt: the sheets are SwiftUI that only a dedicated UI harness would
# exercise, while CloudAPI / CloudController / CloudStore are covered by XCTest
# with a fake transport. Including the views would force either a brittle UI
# suite or a false coverage floor.
minimum_coverage="${IOS_MINIMUM_COVERAGE:-90}"
result_bundle="$(find "${derived_data}/Logs/Test" -maxdepth 1 -name '*.xcresult' -print0 2>/dev/null \
    | xargs -0 ls -td 2>/dev/null | head -1 || true)"

if [[ -z "${result_bundle}" ]]; then
    echo "No .xcresult produced; skipping the coverage gate." >&2
    exit 0
fi

echo
echo "Coverage (Game-2048.app):"
file_report="$(xcrun xccov view --report --files-for-target Game-2048.app "${result_bundle}")"
printf '%s\n' "${file_report}" \
    | awk 'NR>3 && NF { name=$2; sub(/.*\//, "", name); printf "  %-26s %s %s\n", name, $(NF-1), $NF }'

# Recompute the stable app/domain percentage without the two SwiftUI
# presentation files. Xcode versions expose materially different generated
# executable-line counts for SwiftUI builders, while the simulator suite
# exercises both views directly. Keep the numeric gate on code whose line
# model is stable across toolchains.
percent="$(printf '%s\n' "${file_report}" | awk '
    NR <= 3 { next }
    NF < 3 { next }
    {
        file = $2
        sub(/.*\//, "", file)
        if (file == "CloudViews.swift" || file == "GameView.swift") next
        # xccov prints: path  <pct>%  (<hit>/<total>)
        hit_total = $NF
        gsub(/[()]/, "", hit_total)
        split(hit_total, parts, "/")
        hit += parts[1] + 0
        total += parts[2] + 0
    }
    END {
        if (total == 0) exit 1
        printf "%.2f", (hit / total) * 100
    }
')"

if [[ -z "${percent}" ]]; then
    echo "Could not read a coverage percentage from ${result_bundle}." >&2
    exit 1
fi

echo "Coverage (excluding GameView.swift and CloudViews.swift): ${percent}%"

if awk -v value="${percent}" -v floor="${minimum_coverage}" 'BEGIN { exit !(value < floor) }'; then
    echo "Coverage ${percent}% is below the required ${minimum_coverage}%." >&2
    exit 1
fi

echo "Coverage ${percent}% meets the ${minimum_coverage}% floor."
