#!/usr/bin/env node
/**
 * Drives the real web client in a real browser against a real API.
 *
 * The unit suite proves each piece in isolation with an injected `fetch`; this
 * proves the pieces are actually wired to each other and to a live deployment
 * — script order, element ids, dialog behaviour, CORS. Those are exactly the
 * failures a fake cannot have.
 *
 * Usage: node scripts/verify-cloud-web.mjs [apiBaseUrl]
 *
 * Writes screenshots to output/cloud/.
 */
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createStaticServer } from "./lib/static-server.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const apiBaseUrl = (process.argv[2] ?? "https://game-2048-cloud-api.vercel.app").replace(/\/$/, "");
const outputDirectory = path.join(root, "output", "cloud");
fs.mkdirSync(outputDirectory, { recursive: true });

const suffix = crypto.randomBytes(3).toString("hex");
const account = { username: `web${suffix}`, email: `web-${suffix}@example.test`, password: "BrowserTest1" };

const checks = [];
function record(name, ok, detail = "") {
    checks.push({ name, ok, detail });
    console.log(`  ${ok ? "ok  " : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
}

const server = createStaticServer(root);
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch();

try {
    const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    const page = await context.newPage();

    const consoleErrors = [];
    page.on("console", message => {
        if (message.type() === "error") consoleErrors.push(message.text());
    });

    // Point the page at the API under test before any script runs.
    await page.addInitScript(base => {
        window.GAME2048_API_BASE_URL = base;
    }, apiBaseUrl);

    console.log(`Verifying ${origin} against ${apiBaseUrl}\n`);
    await page.goto(`${origin}/index.html`, { waitUntil: "networkidle" });

    record("the board renders", (await page.locator(".cell").count()) === 16);
    record("the guest banner invites without blocking", await page.locator("#cloudBanner").isVisible());
    record("the board is playable before signing in", await page.locator("#gridContainer").isVisible());

    await page.keyboard.press("ArrowLeft");
    await page.keyboard.press("ArrowRight");
    const movesBefore = (await page.evaluate(() => JSON.parse(window.render_game_to_text()))).moves;
    record("moves are counted for the cloud", movesBefore >= 1, `${movesBefore} moves`);

    await page.screenshot({ path: path.join(outputDirectory, "01-guest.png"), fullPage: false });

    await page.locator("#cloudBannerCreate").click();
    await page.waitForSelector("#authDialog[open]");
    record("the sign-up dialog opens", await page.locator("#authTitle").isVisible());
    await page.screenshot({ path: path.join(outputDirectory, "02-sign-up.png") });

    await page.fill("#authUsername", account.username);
    await page.fill("#authEmail", account.email);
    await page.fill("#authPassword", account.password);
    await page.locator("#authSubmit").click();

    await page.waitForFunction(() => document.getElementById("accountButtonLabel").textContent !== "Sign in", null, { timeout: 20_000 });
    record("the account is created and adopted", true, await page.locator("#accountButtonLabel").textContent());
    record("the invitation disappears once signed in", !(await page.locator("#cloudBanner").isVisible()));

    await page.waitForFunction(() => /sync|account/i.test(document.getElementById("cloudStatus").textContent), null, { timeout: 20_000 });
    record("the round syncs on sign-in", true, await page.locator("#cloudStatus").textContent());
    await page.screenshot({ path: path.join(outputDirectory, "03-signed-in.png") });

    // A second browser context is a genuinely different device as far as the
    // API is concerned: separate storage, separate session.
    const second = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    const otherDevice = await second.newPage();
    await otherDevice.addInitScript(base => {
        window.GAME2048_API_BASE_URL = base;
    }, apiBaseUrl);
    await otherDevice.goto(`${origin}/index.html`, { waitUntil: "networkidle" });

    await otherDevice.locator("#cloudBannerSignIn").click();
    await otherDevice.waitForSelector("#authDialog[open]");
    await otherDevice.fill("#authIdentifier", account.username);
    await otherDevice.fill("#authPassword", account.password);
    await otherDevice.locator("#authSubmit").click();
    await otherDevice.waitForFunction(() => document.getElementById("accountButtonLabel").textContent !== "Sign in", null, { timeout: 20_000 });
    record("signing in on a second device works", true);

    await otherDevice.waitForFunction(
        () => /sync|account|round/i.test(document.getElementById("cloudStatus").textContent),
        null,
        { timeout: 20_000 }
    );
    record("the second device reconciles with the first", true, await otherDevice.locator("#cloudStatus").textContent());
    await otherDevice.screenshot({ path: path.join(outputDirectory, "04-second-device.png") });

    await page.locator("#leaderboardButton").click();
    await page.waitForSelector("#leaderboardDialog[open]");
    await page.waitForFunction(() => document.getElementById("leaderboardNote").textContent !== "Loading…", null, { timeout: 20_000 });
    record("the leaderboard loads", true, await page.locator("#leaderboardNote").textContent());
    await page.screenshot({ path: path.join(outputDirectory, "05-leaderboard.png") });
    await page.locator("#leaderboardClose").click();

    await page.locator("#accountButton").click();
    await page.waitForSelector("#accountDialog[open]");
    record("the account panel shows the player's numbers", (await page.locator("#accountSummary").textContent()).includes("Best"));
    await page.screenshot({ path: path.join(outputDirectory, "06-account.png") });

    // Mobile layout, where the banner and the leaderboard have the least room.
    const mobile = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
    const phone = await mobile.newPage();
    await phone.addInitScript(base => {
        window.GAME2048_API_BASE_URL = base;
    }, apiBaseUrl);
    await phone.goto(`${origin}/index.html`, { waitUntil: "networkidle" });
    await phone.screenshot({ path: path.join(outputDirectory, "07-mobile-guest.png") });
    record("the mobile layout keeps the invitation readable", await phone.locator("#cloudBanner").isVisible());

    await page.locator("#accountSignOut").click();
    await page.waitForFunction(() => document.getElementById("accountButtonLabel").textContent === "Sign in", null, { timeout: 20_000 });
    record("signing out returns to guest play", await page.locator("#gridContainer").isVisible());

    record("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 3).join(" | "));

    // Clean up the account this run created.
    const cleanup = await fetch(`${apiBaseUrl}/api/v1/auth/login`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ identifier: account.username, password: account.password })
    }).then(response => response.json());
    await fetch(`${apiBaseUrl}/api/v1/auth/me`, {
        method: "DELETE",
        headers: { "content-type": "application/json", authorization: `Bearer ${cleanup.accessToken}` },
        body: JSON.stringify({ password: account.password, confirm: "DELETE" })
    });
    record("the test account is removed", true);
} finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
}

const failed = checks.filter(check => !check.ok);
console.log(`\n${checks.length - failed.length} passed, ${failed.length} failed`);
console.log(`Screenshots in ${path.relative(process.cwd(), outputDirectory)}`);
if (failed.length > 0) process.exit(1);
