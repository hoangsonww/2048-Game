#!/usr/bin/env node
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { createStaticServer } from "./lib/static-server.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const portIndex = process.argv.indexOf("--port");
const requestedPort = portIndex >= 0 ? Number(process.argv[portIndex + 1]) : Number(process.env.PORT ?? 8080);

if (!Number.isInteger(requestedPort) || requestedPort < 0 || requestedPort > 65535) {
    console.error("Usage: node scripts/serve-web.mjs [--port 0-65535]");
    process.exit(2);
}

const server = createStaticServer(root);
server.listen(requestedPort, "0.0.0.0", () => {
    const address = server.address();
    const activePort = typeof address === "object" && address ? address.port : requestedPort;
    console.log(`2048 web app: http://localhost:${activePort}`);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
    process.on(signal, () => server.close(() => process.exit(0)));
}
