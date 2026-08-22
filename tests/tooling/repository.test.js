"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "../..");

test("repository validator succeeds", () => {
    const result = spawnSync(process.execPath, ["scripts/validate-repository.mjs"], {
        cwd: root,
        encoding: "utf8"
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout, /Repository structure/);
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
