/**
 * Serverless-safe Mongo connection.
 *
 * Vercel keeps a warm Node process between invocations but gives no lifecycle
 * hook to close a pool, so a naive `mongoose.connect()` per request opens a new
 * connection every cold path and exhausts the Atlas connection limit under any
 * real traffic. The promise is cached on `globalThis` — not on a module local —
 * because the module registry itself is not guaranteed to survive between
 * invocations while the global object is.
 */
import mongoose from "mongoose";
import config from "./env.js";
import logger from "../lib/logger.js";

const CACHE_KEY = Symbol.for("2048.cloud.mongoose");

function cache() {
    if (!globalThis[CACHE_KEY]) {
        globalThis[CACHE_KEY] = { connection: null, promise: null };
    }
    return globalThis[CACHE_KEY];
}

mongoose.set("strictQuery", true);
// An unindexed query that silently works in development and times out against
// a real collection is the classic Mongo production surprise. Autoindex is on
// outside production; production indexes are created by `ensureIndexes()`.
mongoose.set("autoIndex", !config.isProduction);

export function connectionState() {
    const states = ["disconnected", "connected", "connecting", "disconnecting", "uninitialized"];
    return states[mongoose.connection.readyState] ?? "unknown";
}

export function isConnected() {
    return mongoose.connection.readyState === 1;
}

export async function connectToDatabase() {
    if (!config.mongo.uri) {
        throw new Error("MONGODB_URI is not configured.");
    }

    const store = cache();
    if (store.connection && isConnected()) return store.connection;

    if (!store.promise) {
        store.promise = mongoose
            .connect(config.mongo.uri, {
                dbName: config.mongo.dbName,
                serverSelectionTimeoutMS: config.mongo.serverSelectionTimeoutMS,
                maxPoolSize: config.mongo.maxPoolSize,
                // A serverless function is killed between requests; a socket kept
                // open past its usefulness is a connection slot held for nothing.
                socketTimeoutMS: 45_000,
                family: 4
            })
            .then(instance => {
                logger.info("database.connected", { database: config.mongo.dbName });
                return instance.connection;
            })
            .catch(error => {
                // Drop the rejected promise so the next request retries instead of
                // replaying the same failure for the lifetime of the container.
                store.promise = null;
                logger.error("database.connect_failed", { message: error.message });
                throw error;
            });
    }

    store.connection = await store.promise;
    return store.connection;
}

export async function disconnectFromDatabase() {
    const store = cache();
    store.connection = null;
    store.promise = null;
    if (mongoose.connection.readyState !== 0) {
        await mongoose.disconnect();
    }
}

export async function pingDatabase() {
    const started = process.hrtime.bigint();
    await connectToDatabase();
    await mongoose.connection.db.admin().command({ ping: 1 });
    return Number(process.hrtime.bigint() - started) / 1_000_000;
}

export default { connectToDatabase, disconnectFromDatabase, pingDatabase, isConnected, connectionState };
