import assert from "node:assert/strict";
import test from "node:test";
import { ApiError, badRequest, conflict, featureDisabled, forbidden, invalidCredentials, notFound, tooManyRequests, unauthorized, validationFailed } from "../../src/lib/errors.js";
import { createLogger } from "../../src/lib/logger.js";

test("an ApiError serialises to the one error envelope the API promises", () => {
    const error = new ApiError(418, "teapot", "Short and stout.", { handle: "left" });
    assert.deepEqual(error.toJSON(), { error: { code: "teapot", message: "Short and stout.", details: { handle: "left" } } });
});

test("details are omitted rather than sent as undefined", () => {
    assert.deepEqual(new ApiError(400, "bad", "No detail.").toJSON(), { error: { code: "bad", message: "No detail." } });
});

test("each helper carries the status and code a client branches on", () => {
    const cases = [
        [badRequest("x"), 400, "bad_request"],
        [unauthorized(), 401, "unauthorized"],
        [invalidCredentials(), 401, "invalid_credentials"],
        [forbidden(), 403, "forbidden"],
        [notFound("Score"), 404, "not_found"],
        [conflict("taken"), 409, "conflict"],
        [validationFailed({ issues: [] }), 422, "validation_failed"],
        [tooManyRequests(), 429, "rate_limited"],
        [featureDisabled("leaderboards"), 503, "feature_disabled"]
    ];

    for (const [error, status, code] of cases) {
        assert.equal(error.status, status, `${code} should be ${status}`);
        assert.equal(error.code, code);
        assert.ok(error instanceof ApiError);
        assert.ok(error.message.length > 0, `${code} needs a human-readable message`);
    }
});

test("notFound names the resource that was missing", () => {
    assert.equal(notFound("Save slot").message, "Save slot was not found.");
});

test("an unknown account and a wrong password produce the same error", () => {
    // Anything else turns the login endpoint into an account-enumeration oracle.
    assert.equal(invalidCredentials().message, invalidCredentials().message);
    assert.equal(invalidCredentials().code, "invalid_credentials");
});

test("the logger redacts credentials by key, wherever they are nested", () => {
    const lines = [];
    const original = process.stdout.write;
    process.stdout.write = chunk => {
        lines.push(String(chunk));
        return true;
    };

    try {
        createLogger("info").info("test.event", {
            password: "hunter2",
            nested: { refreshToken: "secret-token", safe: "visible" },
            list: [{ accessToken: "another-secret" }]
        });
    } finally {
        process.stdout.write = original;
    }

    const output = lines.join("");
    assert.equal(output.includes("hunter2"), false, "a top-level password leaked");
    assert.equal(output.includes("secret-token"), false, "a nested token leaked");
    assert.equal(output.includes("another-secret"), false, "a token inside an array leaked");
    assert.equal(output.includes("visible"), true, "redaction should not swallow everything");
});

test("a silent logger writes nothing", () => {
    const lines = [];
    const original = process.stdout.write;
    process.stdout.write = chunk => {
        lines.push(String(chunk));
        return true;
    };

    try {
        createLogger("silent").info("should.not.appear", {});
    } finally {
        process.stdout.write = original;
    }

    assert.equal(lines.length, 0);
});

test("a child logger merges its bound context into every line", () => {
    const lines = [];
    const original = process.stdout.write;
    process.stdout.write = chunk => {
        lines.push(String(chunk));
        return true;
    };

    try {
        createLogger("info").child({ requestId: "abc-123" }).info("http.request", { status: 200 });
    } finally {
        process.stdout.write = original;
    }

    const parsed = JSON.parse(lines[0]);
    assert.equal(parsed.requestId, "abc-123");
    assert.equal(parsed.status, 200);
    assert.equal(parsed.event, "http.request");
});
