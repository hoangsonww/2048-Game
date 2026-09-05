#!/usr/bin/env bash

# One version, four places that have to agree.
#
# They did not. `package.json` said 1.2.0, the Android manifest said 1.0 with a
# versionCode of 1, the Xcode project said 1.0, and the newest GitHub release
# was v2.0.0 — four different answers to the same question, so the About screen,
# the Play listing, and the release page each described a different build.
#
# `VERSION` at the repository root is now the only place a human edits. This
# script propagates it, and `check` fails CI when something drifts again.
#
# Usage:
#   scripts/version.sh              # print the current version
#   scripts/version.sh check        # verify every file agrees (CI)
#   scripts/version.sh sync         # rewrite the derived files from VERSION
#   scripts/version.sh set 2.1.0    # write VERSION, then sync
#   scripts/version.sh bump patch   # patch | minor | major, then sync

set -Eeuo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

readonly VERSION_FILE="${PROJECT_ROOT}/VERSION"
readonly PACKAGE="${PROJECT_ROOT}/package.json"
readonly GRADLE="${PROJECT_ROOT}/Android-Version/Game2048/app/build.gradle.kts"
readonly PBXPROJ="${PROJECT_ROOT}/2048 Game.xcodeproj/project.pbxproj"

current() {
    tr -d '[:space:]' < "${VERSION_FILE}"
}

valid() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Android wants a monotonic integer as well as the human string. Deriving it
# keeps them in step without a second thing to edit: 2.1.3 -> 20103, ordered as
# long as minor and patch stay below 100.
version_code() {
    local major minor patch
    IFS=. read -r major minor patch <<< "$1"
    printf '%d' $((major * 10000 + minor * 100 + patch))
}

apply() {
    local mode="$1" version="$2" code
    code="$(version_code "${version}")"

    python3 - "${mode}" "${version}" "${code}" "${PACKAGE}" "${GRADLE}" "${PBXPROJ}" <<'PY'
import json
import pathlib
import re
import sys

mode, version, code, package, gradle, pbxproj = sys.argv[1:7]
problems: list[str] = []
changed: list[str] = []


def edit(path: str, pattern: str, replacement: str, label: str, expected: str, group: int = 1) -> None:
    file = pathlib.Path(path)
    text = file.read_text(encoding="utf-8")
    found = re.search(pattern, text)
    actual = found.group(group) if found else "<missing>"

    if mode == "check":
        if actual != expected:
            problems.append(f"  {label}: expected {expected}, found {actual}")
        return

    updated, count = re.subn(pattern, replacement, text, count=0)
    if count == 0:
        problems.append(f"  {label}: no match for {pattern!r} in {path}")
        return
    if updated != text:
        file.write_text(updated, encoding="utf-8")
        changed.append(label)


# package.json is JSON, so it is edited as JSON rather than by regex.
pkg_path = pathlib.Path(package)
pkg = json.loads(pkg_path.read_text(encoding="utf-8"))
if mode == "check":
    if pkg.get("version") != version:
        problems.append(f"  package.json version: expected {version}, found {pkg.get('version')}")
elif pkg.get("version") != version:
    pkg["version"] = version
    pkg_path.write_text(json.dumps(pkg, indent=2) + "\n", encoding="utf-8")
    changed.append("package.json version")

edit(gradle, r'versionName = "([^"]*)"', f'versionName = "{version}"', "Android versionName", version)
edit(gradle, r"versionCode = (\d+)", f"versionCode = {code}", "Android versionCode", code)
# The pbxproj carries one setting per build configuration, so every occurrence
# moves together — a Debug and Release pair that disagree is its own bug.
edit(pbxproj, r"MARKETING_VERSION = ([^;]*);", f"MARKETING_VERSION = {version};", "MARKETING_VERSION", version)
edit(pbxproj, r"CURRENT_PROJECT_VERSION = ([^;]*);", f"CURRENT_PROJECT_VERSION = {code};", "CURRENT_PROJECT_VERSION", code)

if problems:
    print("\n".join(problems))
    sys.exit(1)
if mode != "check":
    print("  " + ("updated: " + ", ".join(changed) if changed else "already in step"))
PY
}

main() {
    local command="${1:-print}"

    if [[ ! -f "${VERSION_FILE}" ]]; then
        printf 'No VERSION file at %s\n' "${VERSION_FILE}" >&2
        return 1
    fi

    local version
    version="$(current)"
    if ! valid "${version}"; then
        printf "VERSION contains '%s', which is not MAJOR.MINOR.PATCH\n" "${version}" >&2
        return 1
    fi

    case "${command}" in
        print)
            printf '%s\n' "${version}"
            ;;
        check)
            section "Version consistency"
            if apply check "${version}"; then
                printf 'Everything agrees on %s\n' "${version}"
            else
                printf 'Files disagree with VERSION (%s). Run: scripts/version.sh sync\n' "${version}" >&2
                return 1
            fi
            ;;
        sync)
            section "Propagating ${version}"
            apply write "${version}"
            printf 'In step with VERSION\n'
            ;;
        set)
            local target="${2:-}"
            if ! valid "${target}"; then
                printf 'Usage: %s set MAJOR.MINOR.PATCH\n' "$0" >&2
                return 2
            fi
            printf '%s\n' "${target}" > "${VERSION_FILE}"
            section "Set ${target}"
            apply write "${target}"
            printf 'VERSION is now %s\n' "${target}"
            ;;
        bump)
            local kind="${2:-patch}" major minor patch
            IFS=. read -r major minor patch <<< "${version}"
            case "${kind}" in
                major) major=$((major + 1)); minor=0; patch=0 ;;
                minor) minor=$((minor + 1)); patch=0 ;;
                patch) patch=$((patch + 1)) ;;
                *) printf 'Usage: %s bump major|minor|patch\n' "$0" >&2; return 2 ;;
            esac
            main set "${major}.${minor}.${patch}"
            ;;
        *)
            printf 'Usage: %s [print|check|sync|set X.Y.Z|bump major|minor|patch]\n' "$0" >&2
            return 2
            ;;
    esac
}

main "$@"
