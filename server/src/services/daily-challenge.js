/**
 * The daily challenge.
 *
 * Every player gets the same opening board on the same UTC day, and the server
 * stores nothing to make that true: the board is *derived* from the date with
 * a seeded generator, so any client can reproduce it offline and the challenge
 * survives a database wipe.
 *
 * The generator is mulberry32 — 32 bits of state, uniform enough for two tile
 * placements, and short enough to reimplement identically in Swift and Kotlin,
 * which is the actual requirement. A cryptographic generator would be both
 * slower and impossible to mirror byte-for-byte across three languages.
 */
import { CELL_COUNT } from "../lib/game-rules.js";

const EPOCH = Date.UTC(2024, 0, 1);

export function seedForDate(dateKey) {
    // FNV-1a over the date string: stable across platforms, and unlike
    // `hashCode`-style accumulation it does not collide on near-identical keys.
    let hash = 2_166_136_261;
    for (let index = 0; index < dateKey.length; index += 1) {
        hash ^= dateKey.charCodeAt(index);
        hash = Math.imul(hash, 16_777_619);
    }
    return hash >>> 0;
}

export function mulberry32(seed) {
    let state = seed >>> 0;
    return function next() {
        state = (state + 0x6d_2b_79_f5) >>> 0;
        let value = state;
        value = Math.imul(value ^ (value >>> 15), value | 1);
        value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
        return ((value ^ (value >>> 14)) >>> 0) / 4_294_967_296;
    };
}

export function isValidDateKey(dateKey) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) return false;
    const parsed = new Date(`${dateKey}T00:00:00.000Z`);
    return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === dateKey;
}

export function todayKey(now = new Date()) {
    return now.toISOString().slice(0, 10);
}

/**
 * Builds the opening position for a date: the same two tiles, in the same two
 * cells, for everybody.
 */
export function boardForDate(dateKey) {
    const random = mulberry32(seedForDate(dateKey));
    const board = new Array(CELL_COUNT).fill(0);

    for (let placed = 0; placed < 2; placed += 1) {
        const empties = board.reduce((cells, value, index) => {
            if (value === 0) cells.push(index);
            return cells;
        }, []);
        const cell = empties[Math.min(empties.length - 1, Math.floor(random() * empties.length))];
        board[cell] = random() < 0.9 ? 2 : 4;
    }

    return board;
}

/**
 * A small, deterministic modifier so consecutive days do not feel identical.
 * It is presentation and target-setting only — no modifier changes a rule.
 */
const MODIFIERS = Object.freeze([
    { key: "classic", name: "Classic", description: "Standard rules. Chase the highest score you can.", targetScore: 6000 },
    { key: "tile_hunt", name: "Tile Hunt", description: "Build the largest single tile you can manage.", targetScore: 8000 },
    { key: "efficiency", name: "Efficiency", description: "Score as much as possible in as few moves as possible.", targetScore: 5000 },
    { key: "endurance", name: "Endurance", description: "Play the longest survivable round you can.", targetScore: 10_000 }
]);

export function challengeForDate(dateKey) {
    const seed = seedForDate(dateKey);
    const modifier = MODIFIERS[seed % MODIFIERS.length];
    const dayNumber = Math.floor((Date.parse(`${dateKey}T00:00:00.000Z`) - EPOCH) / 86_400_000) + 1;

    return {
        date: dateKey,
        dayNumber,
        seed,
        board: boardForDate(dateKey),
        modifier,
        expiresAt: new Date(Date.parse(`${dateKey}T00:00:00.000Z`) + 86_400_000)
    };
}

export const CHALLENGE_MODIFIERS = MODIFIERS;

export default { seedForDate, mulberry32, boardForDate, challengeForDate, todayKey, isValidDateKey, CHALLENGE_MODIFIERS };
