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

function versionTagRepository(existingTag = false) {
    const temporary = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "2048-release-"));
    const remote = path.join(temporary, "remote.git");
    const work = path.join(temporary, "work");
    const output = path.join(temporary, "github-output");

    run("git", ["init", "--bare", remote]);
    run("git", ["init", "--initial-branch=main", work]);
    run("git", ["config", "user.name", "Release Test"], { cwd: work });
    run("git", ["config", "user.email", "release@example.com"], { cwd: work });
    fs.writeFileSync(path.join(work, "VERSION"), "2.1.0\n");
    run("git", ["add", "VERSION"], { cwd: work });
    run("git", ["commit", "-m", "base"], { cwd: work });
    run("git", ["remote", "add", "origin", remote], { cwd: work });
    run("git", ["push", "-u", "origin", "main"], { cwd: work });
    const mainSha = run("git", ["rev-parse", "HEAD"], { cwd: work }).stdout.trim();

    const hook = `#!/bin/sh
while read -r old new ref; do
    if [ "$ref" = "refs/heads/main" ]; then
        echo "main is protected" >&2
        exit 1
    fi
done
`;
    fs.writeFileSync(path.join(remote, "hooks/pre-receive"), hook, { mode: 0o755 });

    if (existingTag) {
        run("git", ["tag", "-a", "v2.1.0", "-m", "2048 2.1.0"], { cwd: work });
        run("git", ["push", "origin", "v2.1.0"], { cwd: work });
    }

    const result = spawnSync("bash", [path.join(root, "scripts/publish-version-tag.sh"), "2.1.0"], {
        cwd: work,
        encoding: "utf8",
        env: {
            ...process.env,
            GITHUB_OUTPUT: output
        }
    });

    return { mainSha, output, remote, result, temporary };
}

test("repository validator succeeds", () => {
    const result = spawnSync(process.execPath, ["scripts/validate-repository.mjs"], {
        cwd: root,
        encoding: "utf8"
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout, /Repository structure/);
});

test("a merged version pull request publishes the version already on main", () => {
    const workflow = fs.readFileSync(path.join(root, ".github/workflows/cut-release.yml"), "utf8");

    assert.match(workflow, /push:\n\s+branches: \[main\]/);
    assert.doesNotMatch(workflow, /pull_request_target:/);
    assert.match(workflow, /ref: \$\{\{ github\.event\.repository\.default_branch \}\}/);
    assert.match(workflow, /\.\/scripts\/publish-version-tag\.sh "\$\{version\}"/);
    assert.doesNotMatch(workflow, /version\.sh bump/);
    assert.doesNotMatch(workflow, /push-validated-release/);
    assert.doesNotMatch(workflow, /git push origin HEAD:"\$\{\{ github\.event\.repository\.default_branch \}\}"/);
    assert.match(workflow, /gh workflow run release\.yml --ref "\$\{tag\}"/);
});

test("an unpublished version is tagged without updating protected main", context => {
    const fixture = versionTagRepository();
    context.after(() => fs.rmSync(fixture.temporary, { recursive: true, force: true }));

    assert.equal(fixture.result.status, 0, `${fixture.result.stdout}\n${fixture.result.stderr}`);
    assert.equal(run("git", ["--git-dir", fixture.remote, "rev-parse", "main"]).stdout.trim(), fixture.mainSha);
    assert.equal(run("git", ["--git-dir", fixture.remote, "rev-parse", "v2.1.0^{}"]).stdout.trim(), fixture.mainSha);
    assert.match(fs.readFileSync(fixture.output, "utf8"), /^tag=v2\.1\.0\nshould_release=true\n$/);
});

test("an already tagged version skips release without moving the tag", context => {
    const fixture = versionTagRepository(true);
    context.after(() => fs.rmSync(fixture.temporary, { recursive: true, force: true }));

    assert.equal(fixture.result.status, 0, `${fixture.result.stdout}\n${fixture.result.stderr}`);
    assert.equal(run("git", ["--git-dir", fixture.remote, "rev-parse", "main"]).stdout.trim(), fixture.mainSha);
    assert.equal(run("git", ["--git-dir", fixture.remote, "rev-parse", "v2.1.0^{}"]).stdout.trim(), fixture.mainSha);
    assert.match(fs.readFileSync(fixture.output, "utf8"), /^tag=v2\.1\.0\nshould_release=false\n$/);
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
