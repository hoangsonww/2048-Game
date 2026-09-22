"use strict";

// The procedural cue layer.
//
// The rule these tests protect is not "a sound plays". It is that a cue is
// dropped rather than queued whenever it cannot be heard now — because the
// bug they exist for was the opposite: cues piling up against a frozen
// AudioContext clock and then firing as one burst several seconds later.

const test = require("node:test");
const assert = require("node:assert/strict");
const { createGameSounds, STORAGE_KEY, MAX_VOICES } = require("../../Web-Version/sounds.js");
const { FakeStorage } = require("./helpers/fake-dom.js");

/** A stub AudioContext that records oscillator scheduling without making noise. */
function fakeAudioContext({ resumable = true } = {}) {
    const nodes = [];
    const built = [];
    class FakeOsc {
        constructor() {
            this.type = "sine";
            this.frequency = {
                values: [],
                setValueAtTime(v) { this.values.push(["set", v]); },
                exponentialRampToValueAtTime(v) { this.values.push(["ramp", v]); }
            };
            this.startedAt = null;
            this.stoppedAt = null;
            this.disconnected = false;
            this.onended = null;
        }
        connect() { return this; }
        disconnect() { this.disconnected = true; }
        start(when) { this.startedAt = when; }
        stop(when) {
            this.stoppedAt = when;
            // A real node fires `ended` when it finishes; the cleanup handler
            // that releases the graph hangs off it.
            this.onended?.();
        }
    }
    class FakeGain {
        constructor() {
            this.disconnected = false;
            this.gain = {
                setValueAtTime() {},
                exponentialRampToValueAtTime() {}
            };
        }
        connect() { return this; }
        disconnect() { this.disconnected = true; }
    }
    return class {
        constructor() {
            this.state = "suspended";
            this.currentTime = 0;
            this.destination = {};
            this.resumeCalls = 0;
            built.push(this);
        }
        createOscillator() {
            const osc = new FakeOsc();
            nodes.push(osc);
            return osc;
        }
        createGain() { return new FakeGain(); }
        resume() {
            this.resumeCalls += 1;
            if (resumable) this.state = "running";
            return Promise.resolve();
        }
        static get nodes() { return nodes; }
        static get instances() { return built; }
        static reset() { nodes.length = 0; built.length = 0; }
    };
}

/** A sound client already past the first user gesture. */
function unlockedSounds(Ctx, storage = new FakeStorage()) {
    const sounds = createGameSounds({ storage, AudioContextCtor: Ctx });
    sounds.unlock();
    return sounds;
}

test("sound defaults to enabled and persists mute", () => {
    const storage = new FakeStorage();
    const Ctx = fakeAudioContext();
    const sounds = createGameSounds({ storage, AudioContextCtor: Ctx });

    assert.equal(sounds.isEnabled(), true);
    assert.equal(sounds.toggle(), false);
    assert.equal(storage.getItem(STORAGE_KEY), "0");
    assert.equal(sounds.toggle(), true);
    assert.equal(storage.getItem(STORAGE_KEY), "1");

    const again = createGameSounds({ storage, AudioContextCtor: Ctx });
    assert.equal(again.isEnabled(), true);
});

test("a false string in storage starts muted", () => {
    const storage = new FakeStorage();
    storage.setItem(STORAGE_KEY, "false");
    const sounds = createGameSounds({ storage, AudioContextCtor: fakeAudioContext() });
    assert.equal(sounds.isEnabled(), false);
});

test("a storage that throws still constructs", () => {
    const storage = {
        getItem() { throw new Error("quota"); },
        setItem() { throw new Error("quota"); }
    };
    const sounds = createGameSounds({ storage, AudioContextCtor: fakeAudioContext() });
    assert.equal(sounds.isEnabled(), true);
    assert.equal(sounds.setEnabled(false), false);
});

test("a muted client schedules nothing", () => {
    const Ctx = fakeAudioContext();
    Ctx.reset();
    const sounds = unlockedSounds(Ctx);
    sounds.setEnabled(false);
    sounds.move();
    sounds.merge(16);
    sounds.win();
    sounds.gameOver();
    sounds.undo();
    sounds.newGame();
    sounds.invalid();
    assert.equal(Ctx.nodes.length, 0);
});

test("unmuting reopens the context that mute left alone", () => {
    const Ctx = fakeAudioContext();
    Ctx.reset();
    const sounds = unlockedSounds(Ctx);
    sounds.setEnabled(false);
    assert.equal(sounds.setEnabled(true), true);
    sounds.move();
    assert.equal(Ctx.nodes.length, 1);
});

test("every cue schedules oscillators, and each releases its graph", () => {
    const Ctx = fakeAudioContext();
    Ctx.reset();
    const sounds = unlockedSounds(Ctx);
    const context = Ctx.instances[0];
    const cues = [
        () => sounds.move(),
        () => sounds.merge(8),
        () => sounds.undo(),
        () => sounds.newGame(),
        () => sounds.win(),
        () => sounds.gameOver(),
        () => sounds.invalid()
    ];
    // Advance between cues so the voice cap — deliberately tight — does not
    // start dropping them; a player cannot press seven buttons in one frame.
    for (const cue of cues) {
        cue();
        context.currentTime += 1;
    }
    assert.ok(Ctx.nodes.length >= 10);
    assert.ok(Ctx.nodes.every(node => node.startedAt !== null && node.stoppedAt !== null));
    assert.ok(Ctx.nodes.every(node => node.disconnected));
});

test("createGameSounds without injections still constructs", () => {
    const sounds = createGameSounds();
    assert.equal(typeof sounds.move, "function");
    assert.equal(sounds.unlock(), false);
    assert.doesNotThrow(() => sounds.invalid());
});

/* -------------------------------------------------------------------- */
/* The burst bug                                                         */
/* -------------------------------------------------------------------- */

test("no context exists before the first user gesture", () => {
    const Ctx = fakeAudioContext();
    Ctx.reset();
    const sounds = createGameSounds({ storage: new FakeStorage(), AudioContextCtor: Ctx });
    // The whole defect: a context built here would be suspended, its clock
    // frozen at zero, and every cue until the first gesture would stack on
    // that one instant and fire together when it unfroze.
    sounds.newGame();
    sounds.move();
    sounds.merge(4);
    assert.equal(Ctx.instances.length, 0);
    assert.equal(Ctx.nodes.length, 0);
});

test("unlocking builds a running context and the next cue is audible", () => {
    const Ctx = fakeAudioContext();
    Ctx.reset();
    const sounds = createGameSounds({ storage: new FakeStorage(), AudioContextCtor: Ctx });
    assert.equal(sounds.unlock(), true);
    assert.equal(Ctx.instances.length, 1);
    assert.equal(Ctx.instances[0].resumeCalls, 1);
    sounds.move();
    assert.equal(Ctx.nodes.length, 1);
    assert.equal(Ctx.nodes[0].startedAt, 0);
});

test("a context that refuses to resume drops cues instead of queueing them", () => {
    const Ctx = fakeAudioContext({ resumable: false });
    Ctx.reset();
    const sounds = createGameSounds({ storage: new FakeStorage(), AudioContextCtor: Ctx });
    assert.equal(sounds.unlock(), false);
    for (let index = 0; index < 20; index += 1) sounds.move();
    assert.equal(Ctx.nodes.length, 0);
    // Once it does start running, cues resume — they are not replayed.
    Ctx.instances[0].state = "running";
    sounds.move();
    assert.equal(Ctx.nodes.length, 1);
});

test("cues are scheduled against a clock that is actually moving", () => {
    const Ctx = fakeAudioContext();
    Ctx.reset();
    const sounds = unlockedSounds(Ctx);
    const context = Ctx.instances[0];

    sounds.move();
    context.currentTime = 0.4;
    sounds.move();
    context.currentTime = 0.9;
    sounds.move();

    assert.deepEqual(Ctx.nodes.map(node => node.startedAt), [0, 0.4, 0.9]);
});

test("a flood of cues is capped rather than buffered", () => {
    const Ctx = fakeAudioContext();
    Ctx.reset();
    const sounds = unlockedSounds(Ctx);
    for (let index = 0; index < 40; index += 1) sounds.move();
    assert.equal(Ctx.nodes.length, MAX_VOICES);
});

test("voices retire as the clock passes them, freeing the cap", () => {
    const Ctx = fakeAudioContext();
    Ctx.reset();
    const sounds = unlockedSounds(Ctx);
    const context = Ctx.instances[0];
    for (let index = 0; index < 40; index += 1) sounds.move();
    assert.equal(Ctx.nodes.length, MAX_VOICES);

    context.currentTime = 5;
    sounds.move();
    assert.equal(Ctx.nodes.length, MAX_VOICES + 1);
});
