/**
 * Importing this module registers every schema with Mongoose.
 *
 * Model registration is a side effect of import, and a `populate()` against a
 * model that has not been imported fails at runtime with a message that names
 * the model but not the missing import. One barrel avoids that entirely.
 */
export { User } from "./User.js";
export { Session } from "./Session.js";
export { GameSave } from "./GameSave.js";
export { Score } from "./Score.js";
export { UserAchievement } from "./UserAchievement.js";
export { Follow } from "./Follow.js";
export { GameEvent } from "./GameEvent.js";
