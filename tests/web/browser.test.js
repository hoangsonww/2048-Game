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
    assert.equal(await page.locator("#undoButton svg, #newGameButton svg").count(), 2);
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
