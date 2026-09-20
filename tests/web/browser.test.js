"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("playwright");

const root = path.resolve(__dirname, "../..");
const storageKey = "game2048-state-v2";
let server;
let browser;
let baseURL;

test.before(async () => {
    server = http.createServer((request, response) => {
        const requested = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
        const relative = requested === "/" ? "index.html" : requested.replace(/^\//, "");
        const file = path.resolve(root, relative);
        if (!file.startsWith(`${root}${path.sep}`) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
            response.writeHead(404).end("Not found");
            return;
        }
        const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".ico": "image/x-icon", ".json": "application/json" };
        response.writeHead(200, { "Content-Type": types[path.extname(file)] || "application/octet-stream" });
        fs.createReadStream(file).pipe(response);
    });
    await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
    baseURL = `http://127.0.0.1:${server.address().port}`;
    browser = await chromium.launch({ headless: true });
});

test.after(async () => {
    await browser?.close();
    await new Promise(resolve => server?.close(resolve));
});

async function scenario(options = {}) {
    const context = await browser.newContext({ viewport: options.viewport || { width: 1280, height: 900 }, hasTouch: options.hasTouch || false });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    page.on("console", message => { if (message.type() === "error") errors.push(message.text()); });
    await page.goto(baseURL);
    if (options.state !== undefined) {
        await page.evaluate(({ key, state }) => {
            localStorage.clear();
            localStorage.setItem(key, typeof state === "string" ? state : JSON.stringify(state));
        }, { key: storageKey, state: options.state });
        await page.reload();
    }
    return { context, page, errors };
}

async function state(page) {
    return JSON.parse(await page.evaluate(() => window.render_game_to_text()));
}

test("fresh game renders two valid tiles and accessible vector controls", async () => {
    const { context, page, errors } = await scenario();
    const snapshot = await state(page);
    assert.equal(snapshot.board.flat().filter(Boolean).length, 2);
    assert.equal(snapshot.board.flat().every(value => value === 0 || value === 2 || value === 4), true);
    assert.equal(await page.locator("#gridContainer .cell").count(), 16);
    assert.equal(await page.locator('#gridContainer > [role="row"]').count(), 4);
    assert.equal(await page.locator('#gridContainer > [role="row"] > [role="gridcell"]').count(), 16);
    assert.equal(await page.locator("#undoButton svg.solid-icon, #newGameButton svg.solid-icon").count(), 2);
    assert.equal(await page.locator("#soundButton").count(), 1);
    assert.equal(await page.locator("#undoButton").isDisabled(), true);
    assert.deepEqual(errors, []);
    await context.close();
});

test("ineffective keyboard move changes neither board nor history", async () => {
    const seeded = { board: [2, 4, 0, 0, ...Array(12).fill(0)], score: 8, best: 16, won: false };
    const { context, page, errors } = await scenario({ state: seeded });
    await page.keyboard.press("ArrowLeft");
    const snapshot = await state(page);
    assert.deepEqual(snapshot.board.flat(), seeded.board);
    assert.equal(snapshot.score, 8);
    assert.equal(snapshot.canUndo, false);
    assert.match(await page.locator("#statusLine").textContent(), /No tiles can move left/);
    assert.deepEqual(errors, []);
    await context.close();
});

test("WASD merge updates score, persists, and undo restores the exact snapshot", async () => {
    const seeded = { board: [2, 2, 0, 0, ...Array(12).fill(0)], score: 10, best: 12, won: false };
    const { context, page, errors } = await scenario({ state: seeded });
    await page.keyboard.press("a");
    let snapshot = await state(page);
    assert.equal(snapshot.board.flat().includes(4), true);
    assert.equal(snapshot.board.flat().filter(Boolean).length, 2);
    assert.equal(snapshot.score, 14);
    assert.equal(snapshot.best, 14);
    assert.equal(snapshot.canUndo, true);
    await page.locator("#undoButton").click();
    snapshot = await state(page);
    assert.deepEqual(snapshot.board.flat(), seeded.board);
    assert.equal(snapshot.score, 10);
    assert.equal(snapshot.canUndo, false);
    await page.reload();
    assert.deepEqual((await state(page)).board.flat(), seeded.board);
    assert.deepEqual(errors, []);
    await context.close();
});

test("mobile direction control and touch swipe each perform one move", async () => {
    const seeded = { board: [0, 2, 0, 0, ...Array(12).fill(0)], score: 0, best: 0, won: false };
    const first = await scenario({ state: seeded, viewport: { width: 390, height: 844 }, hasTouch: true });
    await first.page.locator('[data-direction="left"]').click();
    let snapshot = await state(first.page);
    assert.equal(snapshot.board[0][0], 2);
    assert.equal(snapshot.board.flat().filter(Boolean).length, 2);
    assert.deepEqual(first.errors, []);
    await first.context.close();

    const second = await scenario({ state: seeded, viewport: { width: 390, height: 844 }, hasTouch: true });
    await second.page.locator("#gridContainer").evaluate(element => {
        const emit = (type, x) => {
            const event = new Event(type, { bubbles: true });
            Object.defineProperty(event, "changedTouches", { value: [{ clientX: x, clientY: 200 }] });
            element.dispatchEvent(event);
        };
        emit("touchstart", 300);
        emit("touchend", 100);
    });
    snapshot = await state(second.page);
    assert.equal(snapshot.board[0][0], 2);
    assert.equal(snapshot.board.flat().filter(Boolean).length, 2);
    assert.deepEqual(second.errors, []);
    await second.context.close();
});

test("a board swipe suppresses page scrolling without blocking it elsewhere", async () => {
    const seeded = { board: [0, 2, 0, 0, ...Array(12).fill(0)], score: 0, best: 0, won: false };
    const { context, page, errors } = await scenario({ state: seeded, viewport: { width: 390, height: 844 }, hasTouch: true });

    const result = await page.evaluate(() => {
        const board = document.getElementById("gridContainer");
        const outside = document.querySelector("header") || document.body;
        const touch = (target, x, y) => new Touch({ identifier: 1, target, clientX: x, clientY: y });
        const fire = (target, type, x, y, withTouches = true) => {
            const event = new TouchEvent(type, {
                bubbles: true,
                cancelable: true,
                touches: withTouches ? [touch(target, x, y)] : [],
                changedTouches: [touch(target, x, y)]
            });
            target.dispatchEvent(event);
            return event;
        };
        const box = board.getBoundingClientRect();
        const x = box.left + 30;
        const y = box.top + 30;

        fire(board, "touchstart", x, y);
        const onBoard = fire(board, "touchmove", x, y + 60);

        // A gesture that never touched the board must stay scrollable.
        const offBoard = fire(outside, "touchmove", 20, 120);

        // A cancelled gesture must release the suppression, or the next swipe
        // is measured from a stale origin and the page stays locked.
        fire(board, "touchcancel", x, y + 60, false);
        const afterCancel = fire(board, "touchmove", x, y + 120);

        return {
            boardTouchAction: getComputedStyle(board).touchAction,
            bodyOverscroll: getComputedStyle(document.body).overscrollBehavior,
            onBoardPrevented: onBoard.defaultPrevented,
            offBoardPrevented: offBoard.defaultPrevented,
            afterCancelPrevented: afterCancel.defaultPrevented
        };
    });

    assert.equal(result.boardTouchAction, "none");
    assert.equal(result.bodyOverscroll, "none");
    assert.equal(result.onBoardPrevented, true, "a board swipe must not scroll the page");
    assert.equal(result.offBoardPrevented, false, "scrolling away from the board must still work");
    assert.equal(result.afterCancelPrevented, false, "a cancelled gesture must release the suppression");
    assert.deepEqual(errors, []);
    await context.close();
});

test("new-game confirmation supports cancel and confirmed reset", async () => {
    const seeded = { board: [4, 2, 0, 0, ...Array(12).fill(0)], score: 64, best: 128, won: false };
    const { context, page, errors } = await scenario({ state: seeded });
    await page.locator("#newGameButton").click();
    assert.equal(await page.locator("#newGameDialog").evaluate(dialog => dialog.open), true);
    await page.locator('#newGameDialog button[value="cancel"]').click();
    assert.deepEqual((await state(page)).board.flat(), seeded.board);
    await page.locator("#newGameButton").click();
    await page.locator("#confirmNewGame").click();
    const snapshot = await state(page);
    assert.equal(snapshot.score, 0);
    assert.equal(snapshot.best, 128);
    assert.equal(snapshot.board.flat().filter(Boolean).length, 2);
    assert.deepEqual(errors, []);
    await context.close();
});

test("auth dialog owns WASD and arrows so the board stays still", async () => {
    const seeded = { board: [2, 2, 0, 0, ...Array(12).fill(0)], score: 10, best: 12, won: false };
    const { context, page, errors } = await scenario({ state: seeded });
    await page.locator("#accountButton").click();
    assert.equal(await page.locator("#authDialog").evaluate(dialog => dialog.open), true);

    await page.locator("#authUsername").fill("player");
    await page.keyboard.press("a");
    await page.keyboard.press("w");
    await page.keyboard.press("ArrowLeft");
    assert.deepEqual((await state(page)).board.flat(), seeded.board, "keys in the auth form must not move tiles");

    // Focus a dialog control that is not an input — still must not drive the board.
    await page.locator("#authCancel").focus();
    await page.keyboard.press("d");
    await page.keyboard.press("ArrowRight");
    assert.deepEqual((await state(page)).board.flat(), seeded.board, "keys while the auth dialog is open must not move tiles");

    await page.locator("#authCancel").click();
    assert.equal(await page.locator("#authDialog").evaluate(dialog => dialog.open), false);
    await page.keyboard.press("a");
    assert.equal((await state(page)).board.flat().includes(4), true, "closing auth restores keyboard moves");
    assert.deepEqual(errors, []);
    await context.close();
});

test("2048 win overlay can continue and game-over restore can restart", async () => {
    const win = await scenario({ state: { board: [1024, 1024, 0, 0, ...Array(12).fill(0)], score: 0, best: 0, won: false } });
    await win.page.keyboard.press("ArrowLeft");
    assert.equal(await win.page.locator("#messageTitle").textContent(), "You made 2048");
    assert.equal((await state(win.page)).mode, "won");
    await win.page.locator("#messageSecondary").click();
    assert.equal(await win.page.locator("#gameMessage").isHidden(), true);
    assert.deepEqual(win.errors, []);
    await win.context.close();

    const locked = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];
    const loss = await scenario({ state: { board: locked, score: 512, best: 1024, won: false } });
    assert.equal((await state(loss.page)).mode, "game-over");
    assert.equal(await loss.page.locator("#messageTitle").textContent(), "No more moves");
    await loss.page.locator("#messagePrimary").click();
    assert.equal((await state(loss.page)).board.flat().filter(Boolean).length, 2);
    assert.deepEqual(loss.errors, []);
    await loss.context.close();
});

test("corrupt saved state is discarded and fullscreen shortcut uses the browser API", async () => {
    const { context, page, errors } = await scenario({ state: { board: [...Array(15).fill(0), 3], score: -4, best: -8, won: false } });
    assert.equal((await state(page)).board.flat().filter(Boolean).length, 2);
    await page.evaluate(() => {
        window.__fullscreenRequested = false;
        document.documentElement.requestFullscreen = () => { window.__fullscreenRequested = true; };
    });
    await page.keyboard.press("f");
    assert.equal(await page.evaluate(() => window.__fullscreenRequested), true);
    assert.deepEqual(errors, []);
    await context.close();
});

test("sound cues follow the real audio clock instead of piling up behind it", async () => {
    // The defect this guards: an AudioContext built at load is suspended, its
    // `currentTime` frozen at zero, and every cue scheduled against it lands
    // on the same instant — silence during play, then the whole backlog at
    // once when the context finally resumes.
    const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    await context.addInitScript(() => {
        window.__scheduled = [];
        window.__contexts = 0;
        const Real = window.AudioContext;
        window.AudioContext = class extends Real {
            constructor(...args) {
                super(...args);
                window.__contexts += 1;
                window.__bornSuspended = this.state === "suspended";
            }
            createOscillator() {
                const oscillator = super.createOscillator();
                const start = oscillator.start.bind(oscillator);
                oscillator.start = when => {
                    window.__scheduled.push({ when, clock: this.currentTime, state: this.state });
                    return start(when);
                };
                return oscillator;
            }
        };
    });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.goto(baseURL);
    await page.waitForFunction(() => Boolean(window.render_game_to_text));

    // Nothing may exist before the player has touched the page.
    assert.equal(await page.evaluate(() => window.__contexts), 0);
    assert.deepEqual(await page.evaluate(() => window.__scheduled), []);

    for (let index = 0; index < 12; index += 1) {
        await page.keyboard.press(index % 2 ? "ArrowLeft" : "ArrowUp");
        await page.waitForTimeout(70);
    }

    const scheduled = await page.evaluate(() => window.__scheduled);
    assert.equal(await page.evaluate(() => window.__contexts), 1, "exactly one context, built on the first gesture");
    assert.equal(await page.evaluate(() => window.__bornSuspended), false, "a context born in a gesture is already running");
    assert.ok(scheduled.length > 0, "cues must actually reach the mixer");
    assert.ok(scheduled.every(cue => cue.state === "running"), "nothing is scheduled against a stopped clock");
    // Every cue lands within a render quantum of the clock reading taken when
    // it was made, never at a fixed instant shared with all the others.
    assert.ok(scheduled.every(cue => cue.when >= cue.clock - 0.02 && cue.when <= cue.clock + 0.35));
    const distinct = new Set(scheduled.map(cue => Math.round(cue.clock * 100)));
    assert.ok(distinct.size >= 6, `cues spread across the timeline, got ${distinct.size} distinct instants`);

    assert.deepEqual(errors, []);
    await context.close();
});

test("the sign-in handover warning is on the page and reachable", async () => {
    const { context, page, errors } = await scenario();
    const dialog = page.locator("#profileSwitchDialog");
    await page.locator("#accountButton").click();
    assert.equal(await page.locator("#authDialog").evaluate(node => node.open), true);
    assert.equal(await dialog.evaluate(node => node.open), false, "nothing to warn about on a fresh board");

    await page.keyboard.press("Escape");
    await page.locator("#gridContainer").waitFor();
    await page.keyboard.press("ArrowLeft");
    await page.keyboard.press("ArrowUp");

    await page.locator("#accountButton").click();
    await page.locator("#authSubmit").click();
    assert.equal(await dialog.evaluate(node => node.open), true, "a played round is warned about before it leaves the screen");
    assert.match(await page.locator("#profileSwitchBody").textContent(), /comes back the moment you sign out/);

    await page.locator("#profileSwitchCancel").click();
    assert.equal(await dialog.evaluate(node => node.open), false);
    assert.ok((await state(page)).moves > 0, "declining leaves the round exactly where it was");
    assert.deepEqual(errors, []);
    await context.close();
});

test("password fields confirm, reveal, and offer a way back in", async () => {
    const { context, page, errors } = await scenario();

    await page.locator("#accountButton").click();
    await page.waitForSelector("#authDialog[open]");

    // Sign-up confirms; sign-in has nothing to confirm.
    assert.equal(await page.locator("#authConfirmField").isVisible(), true);
    await page.locator("#authSwitch").click();
    assert.equal(await page.locator("#authConfirmField").isVisible(), false);
    await page.locator("#authSwitch").click();

    // Each reveal control flips only its own field.
    const reveal = page.locator('[data-reveal="authPassword"]');
    await page.fill("#authPassword", "Password1");
    await page.fill("#authConfirm", "Password1");
    assert.equal(await page.locator("#authPassword").getAttribute("type"), "password");
    await reveal.click();
    assert.equal(await page.locator("#authPassword").getAttribute("type"), "text");
    assert.equal(await page.locator("#authConfirm").getAttribute("type"), "password");
    assert.equal(await reveal.getAttribute("aria-pressed"), "true");
    assert.equal(await reveal.getAttribute("aria-label"), "Hide password");
    await reveal.click();
    assert.equal(await page.locator("#authPassword").getAttribute("type"), "password");

    // A mismatch is caught before anything is sent.
    await page.fill("#authConfirm", "Password2");
    await page.locator("#authSubmit").click();
    assert.equal(await page.locator("#authError").isVisible(), true);
    assert.match(await page.locator("#authError").textContent(), /do not match/);
    assert.equal(await page.locator("#authDialog").evaluate(node => node.open), true);

    // Forgot password swaps to the reset form and back.
    await page.locator("#authForgot").click();
    assert.equal(await page.locator("#authDialog").evaluate(node => node.open), false);
    assert.equal(await page.locator("#resetDialog").evaluate(node => node.open), true);
    await page.locator('[data-reveal="resetPassword"]').click();
    assert.equal(await page.locator("#resetPassword").getAttribute("type"), "text");
    await page.locator("#resetCancel").click();
    assert.equal(await page.locator("#resetDialog").evaluate(node => node.open), false);
    assert.equal(await page.locator("#authDialog").evaluate(node => node.open), true);
    assert.equal(await page.locator("#authTitle").textContent(), "Welcome back");
    // Closing a form puts every password back behind dots.
    assert.equal(await page.locator("#resetPassword").getAttribute("type"), "password");

    assert.deepEqual(errors, []);
    await context.close();
});
