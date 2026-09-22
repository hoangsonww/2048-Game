import mongoose from "mongoose";
import { CELL_COUNT, isValidBoard } from "../lib/game-rules.js";

const { Schema, model, models } = mongoose;

/**
 * A cloud save slot.
 *
 * The board is stored flat, exactly as the web engine holds it, and validated
 * by the same predicate. The natives send and receive nested rows; the
 * conversion happens at the route boundary and nowhere else, which mirrors the
 * rule the clients already follow for local persistence.
 *
 * `revision` is the concurrency control. Every write increments it, and a sync
 * that arrives carrying a stale revision is a conflict rather than a
 * last-writer-wins overwrite — losing a round to a phone that was offline for
 * a week is exactly the failure this field exists to prevent.
 */
const gameSaveSchema = new Schema(
    {
        user: { type: Schema.Types.ObjectId, ref: "User", required: true, index: true },
        slot: { type: String, required: true, default: "current", trim: true, maxlength: 32 },
        label: { type: String, trim: true, maxlength: 60, default: "" },
        board: {
            type: [Number],
            required: true,
            validate: {
                validator: isValidBoard,
                message: `A board must hold exactly ${CELL_COUNT} cells, each zero or a power of two.`
            }
        },
        score: { type: Number, required: true, min: 0 },
        bestScore: { type: Number, default: 0, min: 0 },
        won: { type: Boolean, default: false },
        gameOver: { type: Boolean, default: false },
        moves: { type: Number, default: 0, min: 0 },
        highestTile: { type: Number, default: 0, min: 0 },
        elapsedSeconds: { type: Number, default: 0, min: 0 },
        // The undo slot travels with the save so a device handoff mid-round does
        // not silently consume the player's one undo.
        undoBoard: { type: [Number], default: null },
        undoScore: { type: Number, default: null },
        undoWon: { type: Boolean, default: null },
        revision: { type: Number, default: 1, min: 1 },
        client: { type: String, default: "unknown" },
        deviceId: { type: String, default: "", maxlength: 64 }
    },
    { timestamps: true }
);

gameSaveSchema.index({ user: 1, slot: 1 }, { unique: true });
gameSaveSchema.index({ user: 1, updatedAt: -1 });

gameSaveSchema.methods.toJSON = function toJSON() {
    return {
        slot: this.slot,
        label: this.label,
        board: this.board,
        grid: Array.from({ length: 4 }, (_, row) => this.board.slice(row * 4, row * 4 + 4)),
        score: this.score,
        bestScore: this.bestScore,
        won: this.won,
        gameOver: this.gameOver,
        moves: this.moves,
        highestTile: this.highestTile,
        elapsedSeconds: this.elapsedSeconds,
        undo: this.undoBoard
            ? { board: this.undoBoard, score: this.undoScore ?? 0, won: Boolean(this.undoWon) }
            : null,
        revision: this.revision,
        client: this.client,
        deviceId: this.deviceId,
        createdAt: this.createdAt,
        updatedAt: this.updatedAt
    };
};

export const GameSave = models.GameSave ?? model("GameSave", gameSaveSchema);
export default GameSave;
