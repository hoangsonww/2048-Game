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
        'property="og:image"', 'property="og:image:width"', 'name="twitter:card"',
        'name="twitter:image:alt"', 'application/ld+json', 'rel="manifest"', 'hreflang="x-default"'
    ]) assert.match(html, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    assert.match(html, /Web-Version\/game-engine\.js[\s\S]*Web-Version\/script\.js/);
    const structuredData = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)]
        .map(match => JSON.parse(match[1]));
    assert.equal(structuredData.length > 0, true);
    assert.match(JSON.stringify(structuredData), /"VideoGame"/);
    assert.match(JSON.stringify(structuredData), /"HowTo"/);
});

test("manifest, sitemap, robots, and referenced icon assets are valid", () => {
    const manifest = JSON.parse(read("manifest.json"));
    assert.equal(manifest.name.length > 0, true);
    assert.equal(manifest.icons.some(icon => icon.sizes === "192x192"), true);
    assert.equal(manifest.icons.some(icon => icon.sizes === "512x512"), true);
    assert.equal(manifest.shortcuts.length >= 2, true);
    // Assert the declared screenshot size against the file itself rather than a
    // literal. Recapturing a screenshot changes its dimensions, and a hardcoded
    // string silently becomes a lie about what the manifest advertises.
    assert.equal(manifest.screenshots.length > 0, true);
    for (const screenshot of manifest.screenshots) {
        const file = path.join(root, screenshot.src);
        assert.ok(fs.statSync(file).size > 0, `${screenshot.src} should exist`);
        const header = fs.readFileSync(file).subarray(16, 24);
        const declared = `${header.readUInt32BE(0)}x${header.readUInt32BE(4)}`;
        assert.equal(screenshot.sizes, declared, `${screenshot.src} is ${declared}, manifest says ${screenshot.sizes}`);
    }
    assert.match(read("robots.txt"), /Sitemap: https:\/\//);
    assert.match(read("sitemap.xml"), /<urlset/);
    for (const asset of [
        "images/favicon.svg", "images/favicon.ico", "images/brand-mark.svg",
        "images/share-card.png", "images/2048-192x192.png", "images/2048-512x512.png"
    ]) assert.ok(fs.statSync(path.join(root, asset)).size > 0, `${asset} should exist`);
});

test("About page, LLM discovery, error page, and contributor metadata are complete", () => {
    const about = read("Web-Version/about.html");
    for (const required of ['rel="canonical"', 'property="og:title"', 'name="twitter:card"', 'application/ld+json']) {
        assert.match(about, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    }
    const llms = read("llms.txt");
    assert.match(llms, /^# 2048/m);
    assert.match(llms, /llms-full\.txt/);
    assert.match(read("llms-full.txt"), /## Interface map/);
    assert.match(read("404.html"), /noindex, follow/);
    assert.match(read("humans.txt"), /No accounts, analytics/);
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
