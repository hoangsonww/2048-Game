// Short procedural cues for the web client.
//
// No audio files: every cue is a few oscillators through the Web Audio API so
// the static site stays asset-light and the mute toggle is instant.
//
// Timing is the whole difficulty here. An `AudioContext` built outside a user
// gesture starts suspended, and a suspended context's `currentTime` is frozen
// at zero. Scheduling against that clock does not delay a cue — it stacks
// every cue on the same instant, and the browser fires all of them together
// the moment the context unfreezes. That is heard as "nothing, nothing,
// nothing, then twenty sounds at once".
//
// Two rules prevent it, and both are load-bearing:
//
//   1. The context is not constructed until `unlock()` is called from a real
//      user gesture, so it is born running and its clock is real.
//   2. A cue scheduled while the clock is not running is dropped, never
//      queued. A cue the player cannot hear is worth less than nothing if the
//      price is hearing it later on top of twenty others.
//
// A voice cap bounds the rest: a player holding an arrow key cannot outrun the
// mixer, because cues past the cap are dropped rather than buffered.
(function exposeGameSounds(root, factory) {
    "use strict";
    const sounds = factory();
    if (typeof module === "object" && module.exports) module.exports = sounds;
    if (root) root.Game2048Sounds = sounds;
})(typeof globalThis !== "undefined" ? globalThis : this, () => {
    "use strict";

    const STORAGE_KEY = "game2048-sound-enabled";
    /** Cues sounding at once. Past this, a new cue is dropped, never queued. */
    const MAX_VOICES = 8;

    function createGameSounds({ storage, AudioContextCtor } = {}) {
        const store = storage ?? (typeof localStorage === "object" ? localStorage : null);
        const Ctx = AudioContextCtor
            ?? (typeof window !== "undefined" ? (window.AudioContext || window.webkitAudioContext) : null);

        let enabled = true;
        try {
            if (store) {
                const raw = store.getItem(STORAGE_KEY);
                if (raw === "0" || raw === "false") enabled = false;
            }
        } catch (_) {
            enabled = true;
        }

        let ctx = null;
        let unlocked = false;
        /** Scheduled end times of cues still sounding, in context seconds. */
        const sounding = [];

        function context() {
            // Constructing before a gesture is what produces the frozen clock,
            // so there is deliberately no context at all until `unlock()`.
            if (!Ctx || !unlocked) return null;
            if (!ctx) ctx = new Ctx();
            if (ctx.state === "suspended") ctx.resume().catch(() => {});
            return ctx;
        }

        /** Drops finished voices and reports how many are still sounding. */
        function voices(at) {
            for (let index = sounding.length - 1; index >= 0; index -= 1) {
                if (sounding[index] <= at) sounding.splice(index, 1);
            }
            return sounding.length;
        }

        function tone({ frequency, duration = 0.08, type = "sine", gain = 0.045, delay = 0, slideTo }) {
            if (!enabled) return false;
            const audio = context();
            // `running` is not a formality: on every other state the clock is
            // stopped, and scheduling against a stopped clock is the bug.
            if (!audio || audio.state !== "running") return false;

            const now = audio.currentTime + delay;
            if (voices(audio.currentTime) >= MAX_VOICES) return false;

            const osc = audio.createOscillator();
            const amp = audio.createGain();
            osc.type = type;
            osc.frequency.setValueAtTime(frequency, now);
            if (slideTo) osc.frequency.exponentialRampToValueAtTime(Math.max(1, slideTo), now + duration);
            amp.gain.setValueAtTime(0.0001, now);
            amp.gain.exponentialRampToValueAtTime(gain, now + 0.012);
            amp.gain.exponentialRampToValueAtTime(0.0001, now + duration);
            osc.connect(amp);
            amp.connect(audio.destination);
            const endsAt = now + duration + 0.02;
            sounding.push(endsAt);
            // Release the graph as soon as the note is over. Without this the
            // nodes stay connected to the destination for the life of the page.
            osc.onended = () => {
                osc.disconnect();
                amp.disconnect();
            };
            osc.start(now);
            osc.stop(endsAt);
            return true;
        }

        const api = {
            isEnabled: () => enabled,

            /**
             * Called from the first real user gesture.
             *
             * Constructing the context here rather than on the first cue is
             * what makes that cue audible: a context created inside a gesture
             * starts running, so its clock is already moving when the player's
             * first move lands.
             *
             * @returns {boolean} Whether the context is running and audible.
             */
            unlock() {
                unlocked = true;
                const audio = context();
                return audio?.state === "running";
            },

            setEnabled(next) {
                enabled = Boolean(next);
                try {
                    store?.setItem(STORAGE_KEY, enabled ? "1" : "0");
                } catch (_) {
                    /* quota / private mode — preference is session-only */
                }
                if (enabled) context();
                return enabled;
            },
            toggle() {
                return api.setEnabled(!enabled);
            },
            move() {
                tone({ frequency: 420, duration: 0.05, type: "triangle", gain: 0.03 });
            },
            merge(points = 4) {
                const base = 520 + Math.min(400, Math.log2(Math.max(4, points)) * 55);
                tone({ frequency: base, duration: 0.09, type: "sine", gain: 0.055 });
                tone({ frequency: base * 1.5, duration: 0.07, type: "triangle", gain: 0.025, delay: 0.02 });
            },
            undo() {
                tone({ frequency: 360, duration: 0.07, type: "triangle", gain: 0.035, slideTo: 240 });
            },
            newGame() {
                tone({ frequency: 480, duration: 0.06, type: "sine", gain: 0.04 });
                tone({ frequency: 640, duration: 0.08, type: "sine", gain: 0.035, delay: 0.07 });
            },
            win() {
                [523, 659, 784, 1046].forEach((frequency, index) => {
                    tone({ frequency, duration: 0.14, type: "sine", gain: 0.05, delay: index * 0.09 });
                });
            },
            gameOver() {
                tone({ frequency: 280, duration: 0.18, type: "triangle", gain: 0.04, slideTo: 140 });
                tone({ frequency: 180, duration: 0.22, type: "sine", gain: 0.03, delay: 0.1, slideTo: 90 });
            },
            invalid() {
                tone({ frequency: 160, duration: 0.04, type: "square", gain: 0.015 });
            }
        };

        return api;
    }

    return { createGameSounds, STORAGE_KEY, MAX_VOICES };
});
