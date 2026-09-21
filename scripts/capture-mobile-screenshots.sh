#!/usr/bin/env bash

# Captures the canonical iOS and Android screenshots.
#
# Usage:
#   scripts/capture-mobile-screenshots.sh [ios|android|all] [--promote]
#
# Without --promote the captures land in output/mobile/ only. With it, the
# canonical set is copied into images/ the same way the web capture script
# promotes its own.
#
# Android is driven with `adb`: taps are resolved from the accessibility tree
# by content-description rather than hard-coded coordinates, so a layout
# change moves the tap instead of breaking it. iOS is driven by XCUITest —
# there is no tap CLI for a simulator — through the `GAME2048_SCREENSHOTS`
# scheme argument, which makes the UI suite walk the same states and write
# each frame to a host directory.

set -Eeuo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

TARGET="${1:-all}"
PROMOTE="no"
for argument in "$@"; do
    [[ "${argument}" == "--promote" ]] && PROMOTE="yes"
done

case "${TARGET}" in
    ios|android|all|--promote) ;;
    *) printf 'Usage: %s [ios|android|all] [--promote]\n' "$0" >&2; exit 2 ;;
esac
[[ "${TARGET}" == "--promote" ]] && TARGET="all"

OUTPUT="${PROJECT_ROOT}/output/mobile"
IMAGES="${PROJECT_ROOT}/images"
mkdir -p "${OUTPUT}"

# Canonical repo image  <-  capture name
promote_pairs=(
    "android-main:android-ui.png"
    "android-guest:android-cloud-guest.png"
    "android-signup:android-cloud-signup.png"
    "android-signin:android-cloud-signin.png"
    "android-leaderboard:android-cloud-leaderboard.png"
    "android-reset:android-cloud-reset.png"
    "android-handover:android-cloud-handover.png"
    "ios-main:IOS-UI.png"
    "ios-guest:ios-cloud-guest.png"
    "ios-signup:ios-cloud-signup.png"
    "ios-signin:ios-cloud-signin.png"
    "ios-leaderboard:ios-cloud-leaderboard.png"
    "ios-reset:ios-cloud-reset.png"
    "ios-handover:ios-cloud-handover.png"
)

promote() {
    [[ "${PROMOTE}" == "yes" ]] || return 0
    local copied=0 pair name target
    for pair in "${promote_pairs[@]}"; do
        name="${pair%%:*}"
        target="${pair##*:}"
        if [[ "${TARGET}" != "all" && "${name}" != "${TARGET}-"* ]]; then
            continue
        fi
        if [[ -f "${OUTPUT}/${name}.png" ]]; then
            cp "${OUTPUT}/${name}.png" "${IMAGES}/${target}"
            copied=$((copied + 1))
        fi
    done
    printf 'Promoted %d captures into %s\n' "${copied}" "${IMAGES}"
}

# ---------------------------------------------------------------- Android ---

android_capture() {
    require_command node
    local adb
    adb="$(resolve_adb)"
    local serial
    serial="$("${adb}" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
    [[ -n "${serial}" ]] || { printf 'No connected Android device or emulator.\n' >&2; return 1; }

    section "Capturing Android screenshots from ${serial}"

    # Never let a failed run promote frames left by an earlier build.
    rm -f \
        "${OUTPUT}/android-main.png" \
        "${OUTPUT}/android-guest.png" \
        "${OUTPUT}/android-signup.png" \
        "${OUTPUT}/android-signin.png" \
        "${OUTPUT}/android-leaderboard.png" \
        "${OUTPUT}/android-reset.png" \
        "${OUTPUT}/android-handover.png"

    local package="com.sonnguyenhoang.game2048"
    # Always install the current debug APK. Merely finding the package is not
    # enough: an emulator can retain an older build from a previous branch,
    # which would produce polished but completely stale canonical images.
    section "Installing the current debug APK"
    "${PROJECT_ROOT}/scripts/android.sh" installDebug
    shot() { "${adb}" -s "${serial}" exec-out screencap -p > "${OUTPUT}/$1.png"; }
    relaunch() {
        "${adb}" -s "${serial}" shell pm clear "${package}" >/dev/null
        "${adb}" -s "${serial}" shell monkey -p "${package}" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
        sleep 5
    }

    # Taps resolve through the accessibility tree, so a moved control still
    # gets tapped rather than a fixed coordinate missing it.
    locate() {
        local attribute="$1" value="$2" dump coords
        for _ in 1 2 3 4 5; do
            # Dumping directly to /dev/tty is unreliable on API 34 and can
            # kill the helper before it emits XML. Writing on-device first and
            # reading the completed file gives us an atomic snapshot. Compose
            # can briefly report no root while a sheet animates, so retry only
            # that transient capture boundary.
            if ! "${adb}" -s "${serial}" shell uiautomator dump /sdcard/game2048-window.xml >/dev/null 2>&1; then
                sleep 1
                continue
            fi
            dump="$("${adb}" -s "${serial}" exec-out cat /sdcard/game2048-window.xml)"
            # The single-quoted program is JavaScript; `${}` below belongs to
            # its regex character class and must not expand in the shell.
            # shellcheck disable=SC2016
            coords="$(printf '%s' "${dump}" | node -e '
            let input = "";
            process.stdin.on("data", chunk => (input += chunk));
            process.stdin.on("end", () => {
                const [attribute, wanted] = process.argv.slice(1);
                const escaped = wanted.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
                const node = new RegExp(`${attribute}="${escaped}"[^>]*bounds="\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]"`).exec(input);
                if (!node) { process.exit(3); }
                const [, x1, y1, x2, y2] = node.map(Number);
                process.stdout.write(`${Math.round((x1 + x2) / 2)} ${Math.round((y1 + y2) / 2)}`);
            });
        ' "${attribute}" "${value}" 2>/dev/null || true)"
            if [[ -n "${coords}" ]]; then
                printf '%s' "${coords}"
                return 0
            fi
            sleep 1
        done
        return 1
    }

    tap() {
        local attribute="$1" value="$2" coords
        coords="$(locate "${attribute}" "${value}")" || {
            printf 'No control with %s="%s".\n' "${attribute}" "${value}" >&2
            return 1
        }
        # shellcheck disable=SC2086
        "${adb}" -s "${serial}" shell input tap ${coords}
        sleep 2
    }

    # A modal sheet opens part-expanded, so its lower controls are neither
    # visible nor in the accessibility tree. Drag it to full height first.
    expand_sheet() {
        "${adb}" -s "${serial}" shell input swipe 540 1900 540 700 300
        sleep 2
    }

    back() {
        "${adb}" -s "${serial}" shell input keyevent KEYCODE_BACK
        sleep 2
    }

    swipe_board() {
        "${adb}" -s "${serial}" shell input swipe 540 1300 540 1900 200
        sleep 1
    }

    relaunch
    shot android-guest                      # the invite toast is still up
    swipe_board
    swipe_board
    sleep 6                                 # ... and it auto-hides after 5.5s
    shot android-main

    tap content-desc "Sign in or create an account"
    expand_sheet
    shot android-signup

    # A round is on the board by now, so submitting raises the handover
    # warning rather than a request.
    tap content-desc "Submit create account"
    shot android-handover
    tap content-desc "Keep playing this round"

    tap text "I already have an account"
    expand_sheet
    shot android-signin

    tap content-desc "Open password reset"
    expand_sheet
    # The reset form is slightly taller than the viewport. Move its content
    # just enough to include the final navigation action in the canonical
    # frame without losing the title or field labels.
    "${adb}" -s "${serial}" shell input swipe 540 1820 540 1500 250
    sleep 2
    shot android-reset
    back
    back

    tap content-desc "Leaderboard"
    expand_sheet
    sleep 4                                 # let the request answer, or not
    shot android-leaderboard
    back

    printf 'Wrote Android captures to %s\n' "${OUTPUT}"
}

# -------------------------------------------------------------------- iOS ---

ios_capture() {
    require_macos
    require_command xcodebuild
    require_command xcrun

    local device_id result_bundle export_directory
    device_id="$(resolve_ios_simulator)"
    result_bundle="${OUTPUT}/ios-capture.xcresult"
    export_directory="${OUTPUT}/ios-attachments"
    section "Capturing iOS screenshots from ${device_id}"
    boot_ios_simulator "${device_id}"

    # Never let a failed run promote frames left by an earlier build.
    rm -f \
        "${OUTPUT}/ios-main.png" \
        "${OUTPUT}/ios-guest.png" \
        "${OUTPUT}/ios-signup.png" \
        "${OUTPUT}/ios-signin.png" \
        "${OUTPUT}/ios-leaderboard.png" \
        "${OUTPUT}/ios-reset.png" \
        "${OUTPUT}/ios-handover.png"
    rm -rf "${result_bundle}" "${export_directory}"

    # The UI target keeps named screenshot attachments in an xcresult bundle;
    # exporting the bundle is the supported simulator-to-host file boundary.
    (cd "${PROJECT_ROOT}" && xcodebuild \
        -project "2048 Game.xcodeproj" \
        -scheme Game-2048 \
        -destination "id=${device_id}" \
        -derivedDataPath "${TMPDIR:-/tmp}/Game2048Derived" \
        -resultBundlePath "${result_bundle}" \
        -only-testing:Game-2048UITests/ScreenshotTests \
        test \
        -collect-test-diagnostics never \
        -parallel-testing-enabled NO \
        CODE_SIGNING_ALLOWED=NO \
        | tail -40)

    xcrun xcresulttool export attachments \
        --path "${result_bundle}" \
        --output-path "${export_directory}" \
        --filter '*.png'

    # xcresulttool exports UUID-named files and records the human name in its
    # manifest. Restore the stable capture names before promotion.
    local exported capture
    # The JavaScript template literals below must not expand in the shell.
    # shellcheck disable=SC2016
    while IFS=$'\t' read -r exported capture; do
        [[ -n "${exported}" && -n "${capture}" ]] || continue
        cp "${export_directory}/${exported}" "${OUTPUT}/${capture}.png"
    done < <(node -e '
        const manifest = require(process.argv[1]);
        for (const test of manifest) {
            for (const attachment of test.attachments ?? []) {
                const match = /^(ios-[a-z]+)_/.exec(attachment.suggestedHumanReadableName ?? "");
                if (match) process.stdout.write(`${attachment.exportedFileName}\t${match[1]}\n`);
            }
        }
    ' "${export_directory}/manifest.json")

    # Fail loudly if Xcode's export schema changes rather than promoting an
    # incomplete set.
    for capture in ios-main ios-guest ios-signup ios-signin ios-leaderboard ios-reset ios-handover; do
        [[ -f "${OUTPUT}/${capture}.png" ]] || {
            printf 'Missing exported iOS attachment: %s.png\n' "${capture}" >&2
            return 1
        }
    done

    printf 'Wrote iOS captures to %s\n' "${OUTPUT}"
}

[[ "${TARGET}" == "android" || "${TARGET}" == "all" ]] && android_capture
[[ "${TARGET}" == "ios" || "${TARGET}" == "all" ]] && ios_capture
promote
