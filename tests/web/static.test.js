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
    const graph = structuredData.flatMap(item => item["@graph"] ?? [item]);
    const application = graph.find(item => (Array.isArray(item["@type"]) ? item["@type"] : [item["@type"]]).includes("SoftwareApplication"));
    assert.ok(application, "the playable app should have SoftwareApplication metadata");
    assert.equal(application.offers?.price, "0");
    assert.equal(application.applicationCategory, "GameApplication");
    assert.ok(graph.some(item => item["@type"] === "HowTo"));
    const faq = graph.find(item => item["@type"] === "FAQPage");
    assert.equal(faq?.mainEntity?.length, (html.match(/class="faq-item"/g) ?? []).length, "visible FAQs and FAQ metadata must stay aligned");
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
    const sitemap = read("sitemap.xml");
    assert.match(sitemap, /<urlset/);
    assert.ok(sitemap.includes('xmlns:image="http://www.google.com/schemas/sitemap-image/1.1"'));
    assert.doesNotMatch(sitemap, /<image:title>/, "Google deprecated image:title; only advertise image locations");
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
    assert.match(read("humans.txt"), /Local-first play; optional account/);
    assert.match(read("humans.txt"), /No analytics or advertising SDKs/);
    assert.match(read("llms-full.txt"), /Cloud API/);
    assert.match(read("index.html"), /cloud\.js/);
    assert.match(read("index.html"), /account\.js/);
});

test("interactive controls use vector SVG icons instead of text glyphs", () => {
    const html = read("index.html");
    for (const id of ["undoButton", "newGameButton", "soundButton"]) {
        const button = html.match(new RegExp(`<button[^>]*id="${id}"[\\s\\S]*?</button>`))?.[0];
        assert.ok(button, `${id} should exist`);
        assert.match(button, /<svg[^>]*viewBox="0 0 24 24"/);
        assert.doesNotMatch(button, /[↻↶↷←→↑↓⟲⟳🔊🔇]/);
    }
    assert.match(html, /sounds\.js/);
    // The muted glyph is swapped via CSS; an HTML `hidden` attribute would
    // win over `.icon-button--muted .solid-icon--sound-off { display:block }`.
    const mutedIcon = html.match(/<svg class="solid-icon solid-icon--sound-off"[^>]*>/)?.[0];
    assert.ok(mutedIcon, "muted sound icon should exist");
    assert.doesNotMatch(mutedIcon, /(?:^|\s)hidden(?:\s|=|>)/);
});

test("every form pattern compiles under the unicodeSets regex flag", () => {
    // Chrome applies `v` semantics to `pattern`, where an unescaped `-` in a
    // character class is a syntax error. A pattern that fails to compile is
    // not a loose pattern — it is no validation at all, silently.
    const html = read("index.html");
    const patterns = [...html.matchAll(/\spattern="([^"]+)"/g)].map(match => match[1]);
    assert.ok(patterns.length > 0, "there should be at least one pattern to check");
    for (const pattern of patterns) {
        assert.doesNotThrow(() => new RegExp(`^(?:${pattern})$`, "v"), `pattern ${pattern} must compile`);
    }
});
