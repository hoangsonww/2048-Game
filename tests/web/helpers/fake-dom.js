"use strict";

// A minimal DOM good enough to run Web-Version/script.js under `node --test`.
//
// The controller is an IIFE that reads the document once and then talks to the
// page only through the elements it captured, so a hand-written stand-in is
// enough to exercise it — and it keeps the fast unit suite free of a browser.
// The Playwright suite still covers the parts only a real engine can prove
// (layout, focus, actual touch-action behaviour).

const ELEMENT_IDS = [
    "gridContainer", "score", "highScore", "undoButton", "newGameButton",
    "newGameDialog", "confirmNewGame", "gameMessage", "messageKicker",
    "messageTitle", "messageBody", "messagePrimary", "messageSecondary", "statusLine"
];

class FakeClassList {
    constructor() { this.tokens = new Set(); }
    add(token) { this.tokens.add(token); }
    remove(token) { this.tokens.delete(token); }
    contains(token) { return this.tokens.has(token); }
    toggle(token, force) {
        const on = force === undefined ? !this.tokens.has(token) : Boolean(force);
        if (on) this.tokens.add(token); else this.tokens.delete(token);
        return on;
    }
}

class FakeElement {
    constructor(tagName = "div") {
        this.tagName = tagName.toUpperCase();
        this.children = [];
        this.attributes = {};
        this.dataset = {};
        this.classList = new FakeClassList();
        this.listeners = new Map();
        this.textContent = "";
        this.hidden = false;
        this.disabled = false;
        this.open = false;
        this.focusCount = 0;
        this._className = "";
    }

    get className() { return this._className; }
    set className(value) {
        this._className = String(value);
        this.classList.tokens = new Set(this._className.split(/\s+/).filter(Boolean));
    }

    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) { return name in this.attributes ? this.attributes[name] : null; }
    appendChild(child) { this.children.push(child); return child; }
    replaceChildren(...next) { this.children = next; }
    focus() { this.focusCount += 1; }
    showModal() { this.open = true; }
    close() { this.open = false; }

    addEventListener(type, handler, options) {
        if (!this.listeners.has(type)) this.listeners.set(type, []);
        this.listeners.get(type).push({ handler, options });
    }

    /** Fires every handler registered for `type` and returns the event. */
    dispatch(type, event = {}) {
        for (const { handler } of this.listeners.get(type) ?? []) handler(event);
        return event;
    }

    /** Whether a listener for `type` was registered as passive. */
    isPassive(type) {
        const [first] = this.listeners.get(type) ?? [];
        return Boolean(first?.options?.passive);
    }

    descendants() {
        return this.children.flatMap(child => [child, ...child.descendants()]);
    }

    querySelectorAll(selector) {
        if (!selector.startsWith(".")) return [];
        const wanted = selector.slice(1);
        return this.descendants().filter(node => node.classList.contains(wanted));
    }
}

class FakeStorage {
    constructor(entries = {}) { this.map = new Map(Object.entries(entries)); }
    getItem(key) { return this.map.has(key) ? this.map.get(key) : null; }
    setItem(key, value) { this.map.set(key, String(value)); }
    removeItem(key) { this.map.delete(key); }
    clear() { this.map.clear(); }
}

/**
 * Installs a fake page on the global object and loads a fresh copy of the
 * controller into it.
 *
 * @param {object} [options]
 * @param {object} [options.storage] initial localStorage entries
 * @param {() => number} [options.random] deterministic replacement for Math.random
 * @returns a handle with the elements, storage, and helpers for driving input
 */
function loadController({ storage = {}, random = () => 0 } = {}) {
    const elements = Object.fromEntries(ELEMENT_IDS.map(id => [id, new FakeElement()]));
    // These two carry `hidden` in index.html, so the controller starts with the
    // end-of-round panel down. Defaulting them to visible would make the very
    // first render look like a finished game.
    elements.gameMessage.hidden = true;
    elements.messageSecondary.hidden = true;
    const directionButtons = ["up", "down", "left", "right"].map(direction => {
        const button = new FakeElement("button");
        button.dataset.direction = direction;
        return button;
    });

    const documentListeners = new Map();
    const fullscreen = { requested: 0, exited: 0 };

    const documentStub = {
        fullscreenElement: null,
        documentElement: { requestFullscreen: () => { fullscreen.requested += 1; } },
        exitFullscreen: () => { fullscreen.exited += 1; },
        createElement: tagName => new FakeElement(tagName),
        getElementById: id => elements[id] ?? null,
        querySelectorAll: selector => (selector === "[data-direction]" ? directionButtons : []),
        addEventListener(type, handler) {
            if (!documentListeners.has(type)) documentListeners.set(type, []);
            documentListeners.get(type).push(handler);
        }
    };

    const localStorage = new FakeStorage(storage);
    const windowStub = { Game2048Engine: require("../../../Web-Version/game-engine.js") };

    // The controller keeps talking to these globals long after it loads — every
    // click and keypress reaches localStorage and document — so each
    // interaction runs inside the same stubbed page, not just the initial load.
    // Restoring afterwards keeps concurrently loaded controllers independent.
    function run(body) {
        const previous = {
            window: global.window,
            document: global.document,
            localStorage: global.localStorage,
            random: Math.random
        };
        global.window = windowStub;
        global.document = documentStub;
        global.localStorage = localStorage;
        Math.random = random;
        try {
            return body();
        } finally {
            Math.random = previous.random;
            global.window = previous.window;
            global.document = previous.document;
            global.localStorage = previous.localStorage;
        }
    }

    // The controller is an IIFE, so a fresh require is what re-runs it.
    const modulePath = require.resolve("../../../Web-Version/script.js");
    delete require.cache[modulePath];
    run(() => require(modulePath));

    // Anything a test fires by hand — a button click, a touch — has to land in
    // the stubbed page too.
    for (const element of [...Object.values(elements), ...directionButtons]) {
        const dispatch = element.dispatch.bind(element);
        element.dispatch = (type, event = {}) => run(() => dispatch(type, event));
    }

    const grid = elements.gridContainer;

    return {
        elements,
        grid,
        directionButtons,
        localStorage,
        fullscreen,
        document: documentStub,

        run,

        /** The controller's own state dump, already parsed. */
        state: () => run(() => JSON.parse(windowStub.render_game_to_text())),
        redraw: () => run(() => windowStub.advanceTime()),

        cells: () => grid.querySelectorAll(".cell"),
        board: () => grid.querySelectorAll(".cell").map(cell => Number(cell.dataset.value)),
        status: () => elements.statusLine.textContent,

        key(key, extra = {}) {
            const event = { key, prevented: 0, preventDefault() { this.prevented += 1; }, ...extra };
            run(() => {
                for (const handler of documentListeners.get("keydown") ?? []) handler(event);
            });
            return event;
        },

        swipe(dx, dy) {
            grid.dispatch("touchstart", { changedTouches: [{ clientX: 100, clientY: 100 }] });
            grid.dispatch("touchend", { changedTouches: [{ clientX: 100 + dx, clientY: 100 + dy }] });
        },

        saved: () => JSON.parse(localStorage.getItem("game2048-state-v2"))
    };
}

module.exports = { loadController, FakeElement, FakeStorage, ELEMENT_IDS };
