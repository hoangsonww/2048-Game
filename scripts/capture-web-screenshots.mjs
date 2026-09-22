#!/usr/bin/env node
/**
 * Deterministic web UI captures for docs and QA.
 *
 * Classic game states are fully offline. Cloud surfaces that need a live API
 * (signed-in status, leaderboard rows, account panel) hit the public Cloud API
 * unless --offline-only is passed.
 *
 * Usage:
 *   node scripts/capture-web-screenshots.mjs [--output DIR] [--promote] [--offline-only]
 *   [--api URL]
 */
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import crypto from "node:crypto";
import { chromium } from "playwright";
import { createStaticServer } from "./lib/static-server.mjs";

const args = process.argv.slice(2);
const flagValue = name => {
    const index = args.indexOf(name);
    return index >= 0 ? args[index + 1] : undefined;
};
const hasFlag = name => args.includes(name);

const outputDirectory = path.resolve(flagValue("--output") ?? "output/playwright/latest");
const apiBaseUrl = (flagValue("--api") ?? "https://game-2048-cloud-api.vercel.app").replace(/\/$/, "");
const promote = hasFlag("--promote");
const offlineOnly = hasFlag("--offline-only");
const imagesDirectory = path.resolve("images");

const storageKey = "game2048-state-v2";
const played = { board: [4, 2, 0, 0, 8, 4, 0, 0, 32, 8, 4, 2, 64, 16, 8, 4], score: 532, best: 4096, won: false };
const winReady = { board: [1024, 1024, 0, 0, 64, 32, 16, 8, 8, 4, 2, 0, 4, 2, 0, 0], score: 19000, best: 19000, won: false };
const loss = { board: [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2], score: 512, best: 1024, won: false };

/** Canonical repo images ← capture name. */
const promoteMap = {
    "desktop-gameplay": "web-version-UI.png",
    "mobile-gameplay": "web-mobile-gameplay.png",
    "desktop-restart": "web-restart-dialog.png",
    "desktop-win": "web-win.png",
    "desktop-loss": "web-loss.png",
    "desktop-about": "web-about.png",
    "desktop-cloud-guest": "web-cloud-guest.png",
    "desktop-cloud-signup": "web-cloud-signup.png",
    "desktop-cloud-signin": "web-cloud-signin.png",
    "desktop-cloud-handover": "web-cloud-handover.png",
    "desktop-cloud-reset": "web-cloud-reset.png",
    "desktop-cloud-signed-in": "web-cloud-signed-in.png",
    "desktop-cloud-leaderboard": "web-cloud-leaderboard.png",
    "desktop-cloud-account": "web-cloud-account.png",
    "mobile-cloud-guest": "web-cloud-mobile-guest.png",
    "mobile-cloud-signup": "web-cloud-mobile-signup.png"
};

await fs.mkdir(outputDirectory, { recursive: true });
const server = createStaticServer(path.resolve("."));
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const baseURL = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ headless: true });
const report = [];

/** Lets tile colour transitions and dialog fades finish before a capture. */
async function settleTransitions(page) {
    await page.waitForTimeout(600);
}

async function capture(name, viewport, options = {}) {
    const context = await browser.newContext({
        viewport,
        hasTouch: options.hasTouch ?? false,
        deviceScaleFactor: options.deviceScaleFactor ?? 1,
        isMobile: options.isMobile ?? false
    });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    page.on("console", message => {
        if (message.type() === "error") errors.push(message.text());
    });

    if (options.apiBaseUrl) {
        await page.addInitScript(base => {
            window.GAME2048_API_BASE_URL = base;
        }, options.apiBaseUrl);
    }

    const route = options.route ?? "/";
    await page.goto(`${baseURL}${route}`, { waitUntil: "networkidle" });
    if (options.state) {
        await page.evaluate(({ key, state }) => localStorage.setItem(key, JSON.stringify(state)), {
            key: storageKey,
            state: options.state
        });
        await page.reload({ waitUntil: "networkidle" });
    }
    if (options.action) await options.action(page);
    await settleTransitions(page);
    await page.screenshot({ path: path.join(outputDirectory, `${name}.png`), fullPage: options.fullPage ?? false });
    const gameState = route === "/" ? JSON.parse(await page.evaluate(() => window.render_game_to_text())) : null;
    report.push({ name, viewport, route, gameState, errors: errors.slice(0, 5) });
    await context.close();
    return page;
}

async function apiReachable() {
    if (offlineOnly) return false;
    try {
        const response = await fetch(`${apiBaseUrl}/api/v1/health`, { signal: AbortSignal.timeout(8_000) });
        return response.ok;
    } catch {
        return false;
    }
}

try {
    for (const [label, viewport, hasTouch] of [
        ["desktop", { width: 1440, height: 1000 }, false],
        ["mobile", { width: 390, height: 844 }, true]
    ]) {
        await capture(`${label}-gameplay`, viewport, { state: played, hasTouch, fullPage: true, isMobile: hasTouch });
        await capture(`${label}-restart`, viewport, {
            state: played,
            hasTouch,
            isMobile: hasTouch,
            action: page => page.locator("#newGameButton").click()
        });
        await capture(`${label}-win`, viewport, {
            state: winReady,
            hasTouch,
            isMobile: hasTouch,
            action: page => page.keyboard.press("ArrowLeft")
        });
        await capture(`${label}-loss`, viewport, { state: loss, hasTouch, isMobile: hasTouch });
        await capture(`${label}-about`, viewport, {
            route: "/Web-Version/about.html",
            hasTouch,
            isMobile: hasTouch,
            fullPage: true
        });
    }

    // Cloud UI that does not need a successful API call — guest invite + auth dialogs.
    await capture("desktop-cloud-guest", { width: 1440, height: 1000 }, {
        state: played,
        apiBaseUrl,
        action: async page => {
            await page.waitForSelector("#cloudBanner", { state: "visible", timeout: 10_000 });
        }
    });
    await capture("desktop-cloud-signup", { width: 1440, height: 900 }, {
        state: played,
        apiBaseUrl,
        action: async page => {
            await page.locator("#cloudBannerCreate").click();
            await page.waitForSelector("#authDialog[open]");
        }
    });
    await capture("desktop-cloud-signin", { width: 1440, height: 900 }, {
        state: played,
        apiBaseUrl,
        action: async page => {
            await page.locator("#cloudBannerSignIn").click();
            await page.waitForSelector("#authDialog[open]");
        }
    });
    await capture("desktop-cloud-reset", { width: 1440, height: 950 }, {
        state: played,
        apiBaseUrl,
        action: async page => {
            await page.locator("#cloudBannerSignIn").click();
            await page.waitForSelector("#authDialog[open]");
            await page.locator("#authForgot").click();
            await page.waitForSelector("#resetDialog[open]");
        }
    });
    // The warning shown before a sign-in takes the round off the screen.
    await capture("desktop-cloud-handover", { width: 1440, height: 900 }, {
        state: played,
        apiBaseUrl,
        action: async page => {
            await page.locator("#cloudBannerSignIn").click();
            await page.waitForSelector("#authDialog[open]");
            await page.locator("#authSubmit").click();
            await page.waitForSelector("#profileSwitchDialog[open]");
        }
    });
    await capture("mobile-cloud-guest", { width: 390, height: 844 }, {
        state: played,
        hasTouch: true,
        isMobile: true,
        deviceScaleFactor: 2,
        apiBaseUrl,
        action: async page => {
            await page.waitForSelector("#cloudBanner", { state: "visible", timeout: 10_000 });
        }
    });
    await capture("mobile-cloud-signup", { width: 390, height: 844 }, {
        state: played,
        hasTouch: true,
        isMobile: true,
        deviceScaleFactor: 2,
        apiBaseUrl,
        action: async page => {
            await page.locator("#cloudBannerCreate").click();
            await page.waitForSelector("#authDialog[open]");
        }
    });

    if (await apiReachable()) {
        const suffix = crypto.randomBytes(3).toString("hex");
        const account = {
            username: `shot${suffix}`,
            email: `shot-${suffix}@example.test`,
            password: "Screenshot1"
        };

        const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
        const page = await context.newPage();
        await page.addInitScript(base => {
            window.GAME2048_API_BASE_URL = base;
        }, apiBaseUrl);
        await page.goto(`${baseURL}/`, { waitUntil: "networkidle" });
        await page.evaluate(({ key, state }) => localStorage.setItem(key, JSON.stringify(state)), {
            key: storageKey,
            state: played
        });
        await page.reload({ waitUntil: "networkidle" });

        await page.locator("#cloudBannerCreate").click();
        await page.waitForSelector("#authDialog[open]");
        await page.fill("#authUsername", account.username);
        await page.fill("#authEmail", account.email);
        await page.fill("#authPassword", account.password);
        await page.fill("#authConfirm", account.password);
        await page.locator("#authSubmit").click();
        // A round is on screen, so the handover warning comes first.
        await page.waitForSelector("#profileSwitchDialog[open]");
        await page.locator("#profileSwitchConfirm").click();
        await page.waitForFunction(() => document.getElementById("accountButtonLabel").textContent !== "Sign in", null, {
            timeout: 20_000
        });
        // Wait for the reconcile to finish, not merely to start: a capture
        // taken mid-sync shows a spinner and a board still easing between the
        // guest round and the account's.
        await page.waitForFunction(() => {
            const status = document.getElementById("cloudStatus");
            return status.getAttribute("aria-busy") !== "true" && /sync|account|round/i.test(status.textContent);
        }, null, { timeout: 20_000 });
        await settleTransitions(page);
        await page.screenshot({ path: path.join(outputDirectory, "desktop-cloud-signed-in.png") });
        report.push({ name: "desktop-cloud-signed-in", live: true, errors: [] });

        await page.locator("#leaderboardButton").click();
        await page.waitForSelector("#leaderboardDialog[open]");
        await page.waitForFunction(() => document.getElementById("leaderboardNote").textContent !== "Loading…", null, {
            timeout: 20_000
        });
        await settleTransitions(page);
        await page.screenshot({ path: path.join(outputDirectory, "desktop-cloud-leaderboard.png") });
        report.push({ name: "desktop-cloud-leaderboard", live: true, errors: [] });
        await page.locator("#leaderboardClose").click();

        await page.locator("#accountButton").click();
        await page.waitForSelector("#accountDialog[open]");
        await settleTransitions(page);
        await page.screenshot({ path: path.join(outputDirectory, "desktop-cloud-account.png") });
        report.push({ name: "desktop-cloud-account", live: true, errors: [] });

        const login = await fetch(`${apiBaseUrl}/api/v1/auth/login`, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ identifier: account.username, password: account.password })
        }).then(response => response.json());
        await fetch(`${apiBaseUrl}/api/v1/auth/me`, {
            method: "DELETE",
            headers: {
                "content-type": "application/json",
                authorization: `Bearer ${login.accessToken}`
            },
            body: JSON.stringify({ password: account.password, confirm: "DELETE" })
        });
        await context.close();
    } else {
        console.warn("Cloud API unreachable or --offline-only: skipping signed-in / leaderboard / account captures.");
    }

    await fs.writeFile(path.join(outputDirectory, "report.json"), `${JSON.stringify(report, null, 2)}\n`);
    const failures = report.filter(entry => (entry.errors ?? []).length > 0);
    if (failures.length > 0) throw new Error(`Browser errors: ${JSON.stringify(failures)}`);

    if (promote) {
        await fs.mkdir(imagesDirectory, { recursive: true });
        let copied = 0;
        for (const [source, target] of Object.entries(promoteMap)) {
            const from = path.join(outputDirectory, `${source}.png`);
            try {
                await fs.access(from);
            } catch {
                continue;
            }
            await fs.copyFile(from, path.join(imagesDirectory, target));
            copied += 1;
        }
        console.log(`Promoted ${copied} captures into ${imagesDirectory}`);
    }

    console.log(`Captured ${report.length} states in ${outputDirectory}`);
} finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
}
