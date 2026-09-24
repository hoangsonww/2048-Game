#!/usr/bin/env bash

set -Eeuo pipefail

version="${1:?usage: publish-version-tag.sh VERSION}"
output_file="${GITHUB_OUTPUT:-/dev/null}"

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid release version: ${version}" >&2
    exit 1
fi

tag="v${version}"
echo "tag=${tag}" >> "${output_file}"

# The checkout uses full history, but fetch tags explicitly so a rerun cannot
# mistake a remote release for an unpublished version.
git fetch --force --tags origin
if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    echo "${tag} already exists; no new tag is needed."
    echo "should_release=false" >> "${output_file}"
    exit 0
fi

GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-github-actions[bot]}" \
GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}" \
    git tag -a "${tag}" -m "2048 ${version}"
git push origin "${tag}"
echo "should_release=true" >> "${output_file}"
echo "Published ${tag} at $(git rev-parse HEAD)."
