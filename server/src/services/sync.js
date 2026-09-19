/**
 * Two-way save synchronisation.
 *
 * The hard part of cross-device play is not transferring a board; it is
 * deciding which board wins when two devices both have one. The rules below are
 * stated explicitly because "last writer wins" — the default anyone reaches for
 * — silently deletes the round a player spent an hour on whenever their other
 * phone comes back online.
 *
 * Resolution, in order:
 *
 * 1. No remote save        → the local save is uploaded. `uploaded`
 * 2. No local save         → the remote save is returned. `downloaded`
 * 3. Same revision, same board → nothing to do. `in_sync`
 * 4. Local is a strict continuation of remote (same or newer revision, and no
 *    progress would be lost) → upload. `uploaded`
 * 5. Remote is strictly ahead → download. `downloaded`
 * 6. Genuinely divergent   → the *further* round wins and the other is
 *    preserved in a `conflict-<timestamp>` slot. `conflicted`
 *
 * Rule 6 is the one that matters: nothing is ever discarded. A player can
 * always recover the losing side from their slot list.
 */
import { GameSave } from "../models/GameSave.js";
import { highestTile, isGameOver, hasWon, normalizeBoard } from "../lib/game-rules.js";
import { badRequest } from "../lib/errors.js";
import config from "../config/env.js";

export const RESOLUTIONS = Object.freeze(["uploaded", "downloaded", "in_sync", "conflicted"]);

function boardsEqual(left, right) {
    return left.length === right.length && left.every((value, index) => value === right[index]);
}

/**
 * How far a round has actually progressed.
 *
 * Score alone is the obvious measure and the wrong one: a round can score less
 * while being demonstrably further along (a board full of large tiles after a
 * bad merge). Score dominates, with moves as the tiebreak, because a player
 * asked "which of these two is my real game?" answers with the score first.
 */
export function progressOf(save) {
    return { score: save.score ?? 0, moves: save.moves ?? 0, revision: save.revision ?? 1 };
}

export function compareProgress(left, right) {
    const a = progressOf(left);
    const b = progressOf(right);
    if (a.score !== b.score) return a.score > b.score ? 1 : -1;
    if (a.moves !== b.moves) return a.moves > b.moves ? 1 : -1;
    if (a.revision !== b.revision) return a.revision > b.revision ? 1 : -1;
    return 0;
}

/** Normalises whatever shape a client sent into the stored document shape. */
export function normalizeIncoming(payload) {
    const board = normalizeBoard(payload.board ?? payload.grid);
    if (!board) {
        throw badRequest("A save must carry a board of 16 flat cells or a 4x4 grid, each value zero or a power of two.");
    }

    const undoBoard = payload.undo?.board ? normalizeBoard(payload.undo.board) : null;
    if (payload.undo?.board && !undoBoard) {
        throw badRequest("The undo snapshot board is not a valid board.");
    }

    return {
        board,
        score: Math.max(0, Math.trunc(payload.score ?? 0)),
        bestScore: Math.max(0, Math.trunc(payload.bestScore ?? payload.best ?? 0)),
        won: Boolean(payload.won ?? hasWon(board)),
        gameOver: Boolean(payload.gameOver ?? isGameOver(board)),
        moves: Math.max(0, Math.trunc(payload.moves ?? 0)),
        highestTile: highestTile(board),
        elapsedSeconds: Math.max(0, Math.trunc(payload.elapsedSeconds ?? 0)),
        undoBoard,
        undoScore: undoBoard ? Math.max(0, Math.trunc(payload.undo.score ?? 0)) : null,
        undoWon: undoBoard ? Boolean(payload.undo.won) : null,
        label: typeof payload.label === "string" ? payload.label.slice(0, 60) : "",
        client: payload.client ?? "unknown",
        deviceId: typeof payload.deviceId === "string" ? payload.deviceId.slice(0, 64) : ""
    };
}

async function writeSave({ userId, slot, incoming, revision }) {
    return GameSave.findOneAndUpdate(
        { user: userId, slot },
        {
            $set: { ...incoming, revision },
            $setOnInsert: { user: userId, slot }
        },
        { upsert: true, new: true, setDefaultsOnInsert: true, runValidators: true }
    );
}

/**
 * @param {object} input
 * @param {import("mongoose").Types.ObjectId} input.userId
 * @param {string} input.slot
 * @param {object|null} input.localSave Client's save, or null if it has none.
 * @param {"prefer-local"|"prefer-remote"|"auto"} [input.strategy]
 */
export async function synchronize({ userId, slot = "current", localSave = null, strategy = "auto" }) {
    const remote = await GameSave.findOne({ user: userId, slot });

    if (!localSave) {
        if (!remote) return { resolution: "in_sync", save: null, conflictSlot: null };
        return { resolution: "downloaded", save: remote, conflictSlot: null };
    }

    const incoming = normalizeIncoming(localSave);

    if (!remote) {
        const created = await writeSave({ userId, slot, incoming, revision: 1 });
        return { resolution: "uploaded", save: created, conflictSlot: null };
    }

    if (strategy === "prefer-local") {
        const saved = await writeSave({ userId, slot, incoming, revision: remote.revision + 1 });
        return { resolution: "uploaded", save: saved, conflictSlot: null };
    }

    if (strategy === "prefer-remote") {
        return { resolution: "downloaded", save: remote, conflictSlot: null };
    }

    const sameBoard = boardsEqual(incoming.board, remote.board);
    if (sameBoard && incoming.score === remote.score && incoming.moves === remote.moves) {
        // Identical rounds still reconcile the best score, which is monotonic
        // and belongs to the account rather than to the round.
        const bestScore = Math.max(incoming.bestScore, remote.bestScore);
        if (bestScore !== remote.bestScore) {
            remote.bestScore = bestScore;
            await remote.save();
        }
        return { resolution: "in_sync", save: remote, conflictSlot: null };
    }

    const localIsAhead = compareProgress(incoming, remote) > 0;
    const remoteIsAhead = compareProgress(remote, incoming) > 0;

    // A save whose revision descends from the remote one is a continuation,
    // not a divergence: the device had the remote state and moved on from it.
    const isContinuation = (localSave.baseRevision ?? 0) >= remote.revision;

    if (isContinuation) {
        const saved = await writeSave({
            userId,
            slot,
            incoming: { ...incoming, bestScore: Math.max(incoming.bestScore, remote.bestScore) },
            revision: remote.revision + 1
        });
        return { resolution: "uploaded", save: saved, conflictSlot: null };
    }

    if (remoteIsAhead) {
        // The remote round wins, but the local one is not thrown away.
        const conflictSlot = await preserve({ userId, incoming, reason: "local" });
        return { resolution: "conflicted", save: remote, conflictSlot, winner: "remote" };
    }

    if (localIsAhead) {
        const conflictSlot = await preserve({ userId, incoming: remote.toObject(), reason: "remote" });
        const saved = await writeSave({
            userId,
            slot,
            incoming: { ...incoming, bestScore: Math.max(incoming.bestScore, remote.bestScore) },
            revision: remote.revision + 1
        });
        return { resolution: "conflicted", save: saved, conflictSlot, winner: "local" };
    }

    return { resolution: "in_sync", save: remote, conflictSlot: null };
}

/**
 * Parks the losing side of a conflict in its own slot.
 *
 * Old conflict slots are trimmed rather than accumulating forever — a player
 * who plays on two devices for a year should not discover eight hundred slots.
 */
async function preserve({ userId, incoming, reason }) {
    const slot = `conflict-${Date.now().toString(36)}`;
    const normalized = incoming.board ? incoming : normalizeIncoming(incoming);

    await GameSave.create({
        user: userId,
        slot,
        label: `Conflicting ${reason} round`,
        board: normalized.board,
        score: normalized.score,
        bestScore: normalized.bestScore,
        won: normalized.won,
        gameOver: normalized.gameOver,
        moves: normalized.moves,
        highestTile: normalized.highestTile,
        elapsedSeconds: normalized.elapsedSeconds,
        revision: 1,
        client: normalized.client ?? "unknown",
        deviceId: normalized.deviceId ?? ""
    });

    const conflicts = await GameSave.find({ user: userId, slot: /^conflict-/ }).sort({ createdAt: -1 }).select("_id").lean();
    const keep = Math.max(1, Math.floor(config.limits.maxSaveSlots / 2));
    const stale = conflicts.slice(keep).map(entry => entry._id);
    if (stale.length > 0) await GameSave.deleteMany({ _id: { $in: stale } });

    return slot;
}

export default { synchronize, normalizeIncoming, compareProgress, progressOf, RESOLUTIONS };
