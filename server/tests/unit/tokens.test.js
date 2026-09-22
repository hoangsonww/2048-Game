import assert from "node:assert/strict";
import test from "node:test";
import jwt from "jsonwebtoken";
import config from "../../src/config/env.js";
import { bearerToken, hashToken, issueTokenPair, newSessionId, verifyAccessToken, verifyRefreshToken } from "../../src/lib/tokens.js";

const user = { _id: "66b2f0c0a1c4de00126ab9f1", username: "ada", roles: ["player"] };

test("an issued pair verifies and carries the session", () => {
    const pair = issueTokenPair(user);
    const access = verifyAccessToken(pair.accessToken);
    const refresh = verifyRefreshToken(pair.refreshToken);

    assert.equal(access.sub, user._id);
    assert.equal(access.username, "ada");
    assert.equal(access.sid, pair.sessionId);
    assert.equal(refresh.sid, pair.sessionId, "both halves must name the same session");
});

test("an access token is not accepted where a refresh token is required", () => {
    // Without the `typ` claim an access token would be a valid refresh token,
    // which would silently give a stolen short-lived token a sixty-day life.
    const pair = issueTokenPair(user);
    assert.throws(() => verifyRefreshToken(pair.accessToken), /not valid|Expected a refresh token/);
    assert.throws(() => verifyAccessToken(pair.refreshToken), /not valid|Expected an access token/);
});

test("a token signed with the wrong secret is refused", () => {
    const forged = jwt.sign({ sub: user._id, typ: "access" }, "an-attacker-chosen-secret", {
        issuer: config.auth.issuer,
        audience: config.auth.audience
    });
    assert.throws(() => verifyAccessToken(forged), /not valid/);
});

test("an expired token reports that it expired", () => {
    const expired = jwt.sign({ sub: user._id, typ: "access" }, config.auth.accessSecret, {
        issuer: config.auth.issuer,
        audience: config.auth.audience,
        expiresIn: -10
    });
    assert.throws(() => verifyAccessToken(expired), /expired/);
});

test("a token for a different audience or issuer is refused", () => {
    const wrongAudience = jwt.sign({ sub: user._id, typ: "access" }, config.auth.accessSecret, {
        issuer: config.auth.issuer,
        audience: "some-other-app"
    });
    assert.throws(() => verifyAccessToken(wrongAudience), /not valid/);
});

test("refresh tokens are compared by digest, never stored in the clear", () => {
    const token = "a-refresh-token";
    assert.equal(hashToken(token), hashToken(token));
    assert.notEqual(hashToken(token), token);
    assert.match(hashToken(token), /^[a-f0-9]{64}$/, "SHA-256 hex");
});

test("two refresh tokens for one session are never byte-identical", () => {
    // `iat` and `exp` have one-second resolution, so without a unique claim a
    // rotation inside the same second would return the token it replaced —
    // rotation that does not rotate, and replay detection that never fires.
    const sessionId = newSessionId();
    const first = issueTokenPair(user, sessionId);
    const second = issueTokenPair(user, sessionId);
    assert.notEqual(first.refreshToken, second.refreshToken);
    assert.equal(verifyRefreshToken(first.refreshToken).sid, verifyRefreshToken(second.refreshToken).sid);
});

test("session identifiers are unique", () => {
    const identifiers = new Set(Array.from({ length: 200 }, newSessionId));
    assert.equal(identifiers.size, 200);
});

test("bearerToken parses only a well-formed Authorization header", () => {
    assert.equal(bearerToken("Bearer abc.def.ghi"), "abc.def.ghi");
    assert.equal(bearerToken("bearer abc"), "abc", "the scheme is case-insensitive");
    assert.equal(bearerToken("Basic abc"), null);
    assert.equal(bearerToken("Bearer"), null);
    assert.equal(bearerToken("Bearer   "), null);
    assert.equal(bearerToken(undefined), null);
});
