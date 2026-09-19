/**
 * Vercel entry point.
 *
 * An Express app is already a `(req, res)` function, so it can be the default
 * export of a serverless function directly. The app is created once at module
 * scope so a warm container reuses it — and, more importantly, reuses the
 * Mongo connection pool cached alongside it.
 *
 * `vercel.json` rewrites every path here, which is what makes one function
 * serve the whole API rather than one function per route.
 */
import { createApp } from "../src/app.js";

const app = createApp();

export default app;
