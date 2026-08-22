#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'iOS tests require macOS and Xcode.\n' >&2
    exit 2
fi

require_command xcodebuild
require_command xcrun
require_command node

device_id="${IOS_SIMULATOR_ID:-}"
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
    exit 1
fi

xcrun simctl boot "${device_id}" 2>/dev/null || true
xcrun simctl bootstatus "${device_id}" -b

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
