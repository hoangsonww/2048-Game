/**
 * Local and container entry point.
 *
 * Vercel does not use this file — it imports the app from `api/index.js` and
 * owns the lifecycle itself. This is what `npm start`, `make api-dev`, and the
 * Docker image run.
 */
import { createApp } from "./app.js";
import config from "./config/env.js";
import logger from "./lib/logger.js";
import { connectToDatabase, disconnectFromDatabase } from "./config/database.js";

const app = createApp();

/**
 * Connecting before listening is deliberate. A long-running process that
 * accepts traffic before its database is reachable reports every cold-start
 * failure as a 503 to a real user; failing to boot is louder and easier to
 * diagnose. Serverless has the opposite constraint, which is why that path
 * connects lazily instead.
 */
try {
    await connectToDatabase();
} catch (error) {
    logger.error("startup.database_unreachable", { message: error.message });
    process.exit(1);
}

const server = app.listen(config.port, () => {
    logger.info("startup.listening", {
        port: config.port,
        environment: config.environment,
        docs: `http://localhost:${config.port}/docs`
    });
});

async function shutdown(signal) {
    logger.info("shutdown.started", { signal });
    server.close(async () => {
        await disconnectFromDatabase();
        logger.info("shutdown.complete", { signal });
        process.exit(0);
    });

    // A connection that refuses to drain must not hold the process open
    // forever; the platform will send SIGKILL anyway, and doing it here keeps
    // the log honest about what happened.
    setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

export default server;
