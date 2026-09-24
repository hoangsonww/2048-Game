import assert from "node:assert/strict";
import test from "node:test";
import request from "supertest";

// Configuration is evaluated at import time. Exercise the production default
// rather than inheriting a developer's local allow-list.
process.env.NODE_ENV = "production";
process.env.LOG_LEVEL = "silent";
process.env.JWT_ACCESS_SECRET = "cors-test-access-secret";
process.env.JWT_REFRESH_SECRET = "cors-test-refresh-secret";
delete process.env.CORS_ORIGINS;
delete process.env.CORS_ALLOW_ALL;

const { createApp } = await import("../../src/app.js");
const app = createApp();

test("the deployed Netlify client is allowed to call the API", async () => {
    const origin = "https://the-2048.netlify.app";
    const response = await request(app).get("/health").set("Origin", origin).expect(200);

    assert.equal(response.headers["access-control-allow-origin"], origin);
});

test("an unknown production origin is not granted CORS access", async () => {
    const response = await request(app).get("/health").set("Origin", "https://example.invalid").expect(200);

    assert.equal(response.headers["access-control-allow-origin"], undefined);
});
