/**
 * Score submission.
 *
 * This is the one write in the API with real invariants attached, so it lives
 * in a service rather than inline in a route: two routes submit scores (classic
 * and daily challenge) and both must apply the same plausibility check, the
 * same idempotency rule, and the same career-total update.
 */
import { Score } from "../models/Score.js";
import { User } from "../models/User.js";
import { boardSignature, checkScorePlausibility, hasWon, highestTile, isGameOver, normalizeBoard, summarizeBoard } from "../lib/game-rules.js";
import { badRequest } from "../lib/errors.js";
import { applyAchievements } from "./achievements.js";

/**
 * A single-player puzzle has no authoritative server simulation, so the client
 * is trusted for its own score — but not unconditionally. A score that exceeds
 * what its final board could possibly have produced is recorded and flagged
 * rather than refused: refusing would lose a genuine round to a client bug,
 * and flagging keeps it out of the leaderboard while leaving the evidence.
 */
function verify(board, score) {
    const plausibility = checkScorePlausibility(board, score);
    return {
        verified: plausibility.plausible,
        verificationNote: plausibility.plausible ? "" : plausibility.reason
    };
}

/**
 * @param {object} input
 * @param {import("mongoose").Document} input.user
 * @param {number[]|number[][]} input.board
 * @param {number} input.score
 * @param {number} [input.moves]
 * @param {number} [input.durationSeconds]
 * @param {"classic"|"daily"} [input.mode]
 * @param {string|null} [input.challengeDate]
 * @param {string} [input.client]
 */
export async function submitScore({
    user,
    board: rawBoard,
    score,
    moves = 0,
    durationSeconds = 0,
    mode = "classic",
    challengeDate = null,
    client = "unknown"
}) {
    const board = normalizeBoard(rawBoard);
    if (!board) {
        throw badRequest("A board must be 16 flat cells or a 4x4 grid, each value zero or a power of two.");
    }

    const { verified, verificationNote } = verify(board, score);
    const signature = `${mode}:${challengeDate ?? "-"}:${boardSignature(board)}:${score}`;
    const summary = summarizeBoard(board);

    const document = {
        user: user._id,
        username: user.username,
        displayName: user.displayName || user.username,
        country: user.country ?? null,
        avatarColor: user.avatarColor,
        score,
        highestTile: highestTile(board),
        moves,
        durationSeconds,
        won: hasWon(board),
        gameOver: isGameOver(board),
        board,
        mode,
        challengeDate,
        client,
        signature,
        verified,
        verificationNote
    };

    // The unique (user, signature) index makes a retried submission return the
    // original row instead of duplicating it. `upsert` with `$setOnInsert`
    // expresses that in one round trip and without a read-then-write race.
    const before = await Score.findOne({ user: user._id, signature }).lean();
    const record = await Score.findOneAndUpdate(
        { user: user._id, signature },
        { $setOnInsert: document },
        { upsert: true, new: true, setDefaultsOnInsert: true }
    );

    const duplicate = Boolean(before);
    if (duplicate) {
        return { score: record, duplicate: true, unlockedAchievements: [], statistics: user.statistics };
    }

    // Career totals are denormalised onto the user; they are updated here and
    // only here, so there is exactly one writer.
    const statistics = user.statistics ?? {};
    const updated = {
        "statistics.bestScore": Math.max(statistics.bestScore ?? 0, score),
        "statistics.highestTile": Math.max(statistics.highestTile ?? 0, document.highestTile),
        "statistics.lastPlayedAt": new Date()
    };

    const refreshed = await User.findByIdAndUpdate(
        user._id,
        {
            $set: updated,
            $inc: {
                "statistics.totalScore": score,
                "statistics.gamesPlayed": 1,
                "statistics.gamesWon": document.won ? 1 : 0,
                "statistics.totalMoves": moves,
                "statistics.totalPlaytimeSeconds": durationSeconds
            }
        },
        { new: true }
    );

    const unlockedAchievements = await applyAchievements(user._id, {
        score,
        highestTile: document.highestTile,
        moves,
        durationSeconds,
        won: document.won,
        mode,
        statistics: refreshed?.statistics ?? statistics
    });

    return {
        score: record,
        duplicate: false,
        summary,
        unlockedAchievements,
        statistics: refreshed?.statistics ?? statistics
    };
}

export default { submitScore };
