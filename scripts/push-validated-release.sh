#!/usr/bin/env bash

set -Eeuo pipefail

default_branch="${1:?usage: push-validated-release.sh DEFAULT_BRANCH [CI_WORKFLOW]}"
ci_workflow="${2:-ci.yml}"
poll_seconds="${RELEASE_CI_POLL_SECONDS:-15}"
timeout_seconds="${RELEASE_CI_TIMEOUT_SECONDS:-3600}"
run_identity="${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}"
candidate_branch="automation/release-${run_identity}"
candidate_pushed=false

cleanup() {
    if [[ "${candidate_pushed}" == true ]]; then
        git push origin --delete "${candidate_branch}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

release_sha="$(git rev-parse HEAD)"
echo "Publishing release candidate ${release_sha} to ${candidate_branch}."
git push origin "HEAD:refs/heads/${candidate_branch}"
candidate_pushed=true

gh workflow run "${ci_workflow}" --ref "${candidate_branch}"
echo "Waiting for ${ci_workflow} to validate ${release_sha}."

deadline=$((SECONDS + timeout_seconds))
while ((SECONDS < deadline)); do
    run="$(gh run list \
        --workflow "${ci_workflow}" \
        --commit "${release_sha}" \
        --branch "${candidate_branch}" \
        --event workflow_dispatch \
        --limit 10 \
        --json databaseId,status,conclusion \
        --jq 'first')"
    status="$(jq -r '.status // empty' <<< "${run}")"
    conclusion="$(jq -r '.conclusion // empty' <<< "${run}")"

    if [[ "${status}" == completed ]]; then
        if [[ "${conclusion}" != success ]]; then
            echo "Release-candidate CI failed for ${release_sha} (${conclusion:-unknown})." >&2
            exit 1
        fi
        echo "Release-candidate CI passed for ${release_sha}."
        break
    fi

    sleep "${poll_seconds}"
done

if [[ "${status:-}" != completed ]]; then
    echo "Timed out waiting for release-candidate CI for ${release_sha}." >&2
    exit 1
fi

# Branch protection evaluates checks on the commit being pushed. Because this
# exact SHA just passed the four required CI jobs, the protected update can
# proceed without bypassing or weakening the rule.
git push origin "HEAD:refs/heads/${default_branch}"
echo "Advanced ${default_branch} to validated release commit ${release_sha}."
