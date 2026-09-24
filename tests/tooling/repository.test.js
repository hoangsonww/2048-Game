"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "../..");

function run(command, args, options = {}) {
    const result = spawnSync(command, args, { encoding: "utf8", ...options });
    assert.equal(result.status, 0, `${command} ${args.join(" ")}\n${result.stdout}\n${result.stderr}`);
    return result;
}

function releaseRepository(conclusion) {
    const temporary = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "2048-release-"));
    const remote = path.join(temporary, "remote.git");
    const work = path.join(temporary, "work");
    const bin = path.join(temporary, "bin");
    const marker = path.join(temporary, "ci-passed");
    const log = path.join(temporary, "gh.log");

    fs.mkdirSync(bin);
    run("git", ["init", "--bare", remote]);
    run("git", ["init", "--initial-branch=main", work]);
    run("git", ["config", "user.name", "Release Test"], { cwd: work });
    run("git", ["config", "user.email", "release@example.com"], { cwd: work });
    fs.writeFileSync(path.join(work, "VERSION"), "2.1.0\n");
    run("git", ["add", "VERSION"], { cwd: work });
    run("git", ["commit", "-m", "base"], { cwd: work });
    run("git", ["remote", "add", "origin", remote], { cwd: work });
    run("git", ["push", "-u", "origin", "main"], { cwd: work });

    const hook = `#!/bin/sh
while read -r old new ref; do
    if [ "$ref" = "refs/heads/main" ] && [ ! -f '${marker}' ]; then
        echo "main requires successful CI" >&2
        exit 1
    fi
done
`;
    fs.writeFileSync(path.join(remote, "hooks/pre-receive"), hook, { mode: 0o755 });

    fs.writeFileSync(path.join(work, "VERSION"), "2.1.1\n");
    run("git", ["add", "VERSION"], { cwd: work });
    run("git", ["commit", "-m", "Release v2.1.1"], { cwd: work });
    const releaseSha = run("git", ["rev-parse", "HEAD"], { cwd: work }).stdout.trim();
    const mainBefore = run("git", ["rev-parse", "origin/main"], { cwd: work }).stdout.trim();

    const gh = `#!/bin/sh
set -eu
printf '%s\\n' "$*" >> "$TEST_GH_LOG"
if [ "$1 $2" = "workflow run" ]; then
    exit 0
fi
if [ "$1 $2" = "run list" ]; then
    if [ '${conclusion}' = success ]; then
        : > "$TEST_CI_MARKER"
    fi
    printf '%s\\n' '{"databaseId":123,"status":"completed","conclusion":"${conclusion}"}'
    exit 0
fi
exit 2
`;
    fs.writeFileSync(path.join(bin, "gh"), gh, { mode: 0o755 });

    const result = spawnSync("bash", [path.join(root, "scripts/push-validated-release.sh"), "main"], {
        cwd: work,
        encoding: "utf8",
        env: {
            ...process.env,
            PATH: `${bin}:${process.env.PATH}`,
            TEST_CI_MARKER: marker,
            TEST_GH_LOG: log,
            RELEASE_CI_POLL_SECONDS: "0",
            RELEASE_CI_TIMEOUT_SECONDS: "5"
        }
    });

    return { conclusion, log, mainBefore, releaseSha, remote, result, temporary };
}

test("repository validator succeeds", () => {
    const result = spawnSync(process.execPath, ["scripts/validate-repository.mjs"], {
        cwd: root,
        encoding: "utf8"
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout, /Repository structure/);
});

test("a merged pull request automatically cuts a patch release from main", () => {
    const workflow = fs.readFileSync(path.join(root, ".github/workflows/cut-release.yml"), "utf8");

    assert.match(workflow, /push:\n\s+branches: \[main\]/);
    assert.doesNotMatch(workflow, /pull_request_target:/);
    assert.match(workflow, /TRIGGER_SHA: \$\{\{ github\.sha \}\}/);
    assert.match(workflow, /published_tags="\$\(gh release list --limit 100 --json isDraft,tagName/);
    assert.match(workflow, /done <<< "\$\{published_tags\}"/);
    assert.doesNotMatch(workflow, /done < <\(gh release list/);
    assert.match(workflow, /git merge-base --is-ancestor "\$\{TRIGGER_SHA\}" "refs\/tags\/\$\{tag\}"/);
    assert.match(workflow, /needs\.release_guard\.outputs\.should_release == 'true'/);
    assert.match(workflow, /inputs\.bump \|\| 'patch'/);
    assert.match(workflow, /ref: \$\{\{ github\.event\.repository\.default_branch \}\}/);
    assert.match(workflow, /\.\/scripts\/push-validated-release\.sh "\$\{\{ github\.event\.repository\.default_branch \}\}"/);
    assert.doesNotMatch(workflow, /git push origin HEAD:"\$\{\{ github\.event\.repository\.default_branch \}\}"/);
    assert.match(workflow, /gh workflow run release\.yml --ref "\$\{tag\}"/);
});

test("a release commit reaches protected main only after CI passes for that commit", context => {
    const fixture = releaseRepository("success");
    context.after(() => fs.rmSync(fixture.temporary, { recursive: true, force: true }));

    assert.equal(fixture.result.status, 0, `${fixture.result.stdout}\n${fixture.result.stderr}`);
    assert.equal(run("git", ["--git-dir", fixture.remote, "rev-parse", "main"]).stdout.trim(), fixture.releaseSha);
    const ghCalls = fs.readFileSync(fixture.log, "utf8").trim().split("\n");
    const dispatchCall = ghCalls.find(call => call.startsWith("workflow run "));
    const runListCall = ghCalls.find(call => call.startsWith("run list "));
    const candidateBranch = dispatchCall.match(/--ref (\S+)/)[1];
    assert.match(candidateBranch, /^automation\/release-/);
    assert.ok(runListCall.includes(`--commit ${fixture.releaseSha}`));
    assert.ok(runListCall.includes(`--branch ${candidateBranch}`));
    assert.equal(run("git", ["--git-dir", fixture.remote, "branch", "--list", "automation/release-*"]).stdout.trim(), "");
});

test("a failed release-candidate CI run leaves main unchanged", context => {
    const fixture = releaseRepository("failure");
    context.after(() => fs.rmSync(fixture.temporary, { recursive: true, force: true }));

    assert.notEqual(fixture.result.status, 0);
    assert.match(`${fixture.result.stdout}\n${fixture.result.stderr}`, /release-candidate CI failed/i);
    assert.equal(run("git", ["--git-dir", fixture.remote, "rev-parse", "main"]).stdout.trim(), fixture.mainBefore);
    assert.equal(run("git", ["--git-dir", fixture.remote, "branch", "--list", "automation/release-*"]).stdout.trim(), "");
});

test("local server publishes discoverable files with safe content types", async context => {
    const { createStaticServer } = await import("../../scripts/lib/static-server.mjs");
    const server = createStaticServer(root);
    await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
    context.after(() => new Promise(resolve => server.close(resolve)));

    const { port } = server.address();
    const baseURL = `http://127.0.0.1:${port}`;
    const home = await fetch(`${baseURL}/`);
    assert.equal(home.status, 200);
    assert.match(home.headers.get("content-type"), /^text\/html/);
    assert.match(await home.text(), /<title>Play 2048/);

    const llms = await fetch(`${baseURL}/llms.txt`);
    assert.equal(llms.status, 200);
    assert.match(llms.headers.get("content-type"), /^text\/plain/);

    const traversal = await fetch(`${baseURL}/%2e%2e%2fpackage.json`);
    assert.equal(traversal.status, 403);

    const missing = await fetch(`${baseURL}/does-not-exist`);
    assert.equal(missing.status, 404);
});
