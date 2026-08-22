#!/usr/bin/env bash

# Builds, installs, and launches the iOS client on a simulator without
# requiring the developer to open Xcode or hunt for a device UDID.
#
# Usage:
#   scripts/ios.sh build      Build for the resolved simulator
#   scripts/ios.sh run        Build, install, and launch on the simulator
#   scripts/ios.sh boot       Boot the resolved simulator and open Simulator.app
#   scripts/ios.sh devices    List available iPhone simulators
#
# Pin a specific device with IOS_SIMULATOR_ID=<udid>.

set -Eeuo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

XCODE_PROJECT="2048 Game.xcodeproj"
XCODE_SCHEME="Game-2048"
DERIVED_DATA="${TMPDIR:-/tmp}/Game2048Derived"

usage() {
    printf 'Usage: %s <build|run|boot|devices>\n' "$0" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage
require_macos
require_command xcodebuild
require_command xcrun

case "$1" in
    devices)
        section "Available iPhone simulators"
        xcrun simctl list devices available | sed -n '/-- iOS/,/^--/p'
        exit 0
        ;;
    build|run|boot) ;;
    *) usage ;;
esac

require_command node
device_id="$(resolve_ios_simulator)"
device_name="$(xcrun simctl list devices -j | node -e '
    let input = "";
    process.stdin.on("data", chunk => input += chunk);
    process.stdin.on("end", () => {
        const target = process.argv[1];
        const devices = Object.values(JSON.parse(input).devices).flat();
        const device = devices.find(item => item.udid === target);
        process.stdout.write(device ? device.name : target);
    });
' "${device_id}")"

printf 'Using simulator: %s (%s)\n' "${device_name}" "${device_id}"

if [[ "$1" == "boot" ]]; then
    section "Booting ${device_name}"
    boot_ios_simulator "${device_id}"
    open -a Simulator
    exit 0
fi

section "Building ${XCODE_SCHEME} for ${device_name}"
(cd "${PROJECT_ROOT}" && xcodebuild \
    -project "${XCODE_PROJECT}" \
    -scheme "${XCODE_SCHEME}" \
    -destination "id=${device_id}" \
    -derivedDataPath "${DERIVED_DATA}" \
    build \
    CODE_SIGNING_ALLOWED=NO)

[[ "$1" == "build" ]] && exit 0

app_path="${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/${XCODE_SCHEME}.app"
if [[ ! -d "${app_path}" ]]; then
    printf 'Built app not found at %s\n' "${app_path}" >&2
    exit 1
fi

bundle_id="$(plutil -extract CFBundleIdentifier raw "${app_path}/Info.plist")"

section "Installing and launching ${bundle_id}"
boot_ios_simulator "${device_id}"
xcrun simctl install "${device_id}" "${app_path}"
xcrun simctl launch "${device_id}" "${bundle_id}"
open -a Simulator

printf '\nLaunched %s on %s.\n' "${bundle_id}" "${device_name}"
