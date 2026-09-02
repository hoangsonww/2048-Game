#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { chromium } from "playwright";
import { createStaticServer } from "./lib/static-server.mjs";

const outputFlag = process.argv.indexOf("--output");
const outputDirectory = path.resolve(outputFlag >= 0 ? process.argv[outputFlag + 1] : "output/playwright/latest");
const storageKey = "game2048-state-v2";
const played = { board: [4, 2, 0, 0, 8, 4, 0, 0, 32, 8, 4, 2, 64, 16, 8, 4], score: 532, best: 4096, won: false };
const winReady = { board: [1024, 1024, 0, 0, 64, 32, 16, 8, 8, 4, 2, 0, 4, 2, 0, 0], score: 19000, best: 19000, won: false };
const loss = { board: [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2], score: 512, best: 1024, won: false };

await fs.mkdir(outputDirectory, { recursive: true });
const server = createStaticServer(path.resolve("."));
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const address = server.address();
const baseURL = `http://127.0.0.1:${address.port}`;
const browser = await chromium.launch({ headless: true });
const report = [];

async function capture(name, viewport, options = {}) {
    const context = await browser.newContext({ viewport, hasTouch: options.hasTouch ?? false });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    page.on("console", message => {
        if (message.type() === "error") errors.push(message.text());
    });
    const route = options.route ?? "/";
    await page.goto(`${baseURL}${route}`, { waitUntil: "networkidle" });
    if (options.state) {
        await page.evaluate(({ key, state }) => localStorage.setItem(key, JSON.stringify(state)), { key: storageKey, state: options.state });
        await page.reload({ waitUntil: "networkidle" });
    }
    if (options.action) await options.action(page);
    await page.screenshot({ path: path.join(outputDirectory, `${name}.png`), fullPage: options.fullPage ?? false });
    const gameState = route === "/" ? JSON.parse(await page.evaluate(() => window.render_game_to_text())) : null;
    report.push({ name, viewport, route, gameState, errors });
    await context.close();
}

try {
    for (const [label, viewport, hasTouch] of [
        ["desktop", { width: 1440, height: 1000 }, false],
        ["mobile", { width: 390, height: 844 }, true]
    ]) {
        await capture(`${label}-gameplay`, viewport, { state: played, hasTouch, fullPage: true });
        await capture(`${label}-restart`, viewport, { state: played, hasTouch, action: page => page.locator("#newGameButton").click() });
        await capture(`${label}-win`, viewport, { state: winReady, hasTouch, action: page => page.keyboard.press("ArrowLeft") });
        await capture(`${label}-loss`, viewport, { state: loss, hasTouch });
        await capture(`${label}-about`, viewport, { route: "/Web-Version/about.html", hasTouch, fullPage: true });
    }
    await fs.writeFile(path.join(outputDirectory, "report.json"), `${JSON.stringify(report, null, 2)}\n`);
    const failures = report.filter(entry => entry.errors.length > 0);
    if (failures.length > 0) throw new Error(`Browser errors: ${JSON.stringify(failures)}`);
    console.log(`Captured ${report.length} states in ${outputDirectory}`);
} finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
}
