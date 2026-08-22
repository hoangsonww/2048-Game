"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");

test("web entry contains complete SEO and social metadata", () => {
    const html = read("index.html");
    for (const required of [
        "<title>", 'name="description"', 'rel="canonical"', 'property="og:title"',
        'property="og:image"', 'name="twitter:card"', 'application/ld+json', 'rel="manifest"'
    ]) assert.match(html, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    assert.match(html, /Web-Version\/game-engine\.js[\s\S]*Web-Version\/script\.js/);
});

test("manifest, sitemap, robots, and referenced icon assets are valid", () => {
    const manifest = JSON.parse(read("manifest.json"));
    assert.equal(manifest.name.length > 0, true);
    assert.equal(manifest.icons.some(icon => icon.sizes === "192x192"), true);
    assert.equal(manifest.icons.some(icon => icon.sizes === "512x512"), true);
    assert.match(read("robots.txt"), /Sitemap: https:\/\//);
    assert.match(read("sitemap.xml"), /<urlset/);
    for (const asset of [
        "images/favicon.svg", "images/favicon.ico", "images/brand-mark.svg",
        "images/share-card.png", "images/2048-192x192.png", "images/2048-512x512.png"
    ]) assert.ok(fs.statSync(path.join(root, asset)).size > 0, `${asset} should exist`);
});

test("interactive controls use vector SVG icons instead of text glyphs", () => {
    const html = read("index.html");
    for (const id of ["undoButton", "newGameButton"]) {
        const button = html.match(new RegExp(`<button[^>]*id="${id}"[\\s\\S]*?</button>`))?.[0];
        assert.ok(button, `${id} should exist`);
        assert.match(button, /<svg[^>]*viewBox="0 0 24 24"/);
        assert.doesNotMatch(button, /[↻↶↷←→↑↓⟲⟳]/);
    }
});
