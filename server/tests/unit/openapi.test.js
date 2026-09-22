import assert from "node:assert/strict";
import test from "node:test";
import { buildOpenApiDocument } from "../../src/docs/openapi.js";
import { toPostmanCollection } from "../../src/docs/ui.js";
import { mountedRoutes } from "../../src/routes/index.js";

const document = buildOpenApiDocument({ serverUrl: "https://example.test" });

/** Express writes `:id`; OpenAPI writes `{id}`. */
function toTemplate(path) {
    return path.replace(/:([A-Za-z0-9_]+)/g, "{$1}");
}

function documentedOperations() {
    const operations = new Set();
    for (const [path, methods] of Object.entries(document.paths)) {
        for (const method of Object.keys(methods)) operations.add(`${method.toUpperCase()} ${path}`);
    }
    return operations;
}

test("every route the app mounts is documented", () => {
    // This is the test that keeps the reference page honest. A new endpoint
    // that nobody documents fails here rather than shipping invisible.
    const documented = documentedOperations();
    const missing = mountedRoutes()
        .map(route => `${route.method} ${toTemplate(route.path)}`)
        .filter(operation => !documented.has(operation));

    assert.deepEqual(missing, [], `undocumented route(s):\n${missing.join("\n")}`);
});

test("every documented operation is actually mounted", () => {
    // The other direction: a renamed route leaves a documented path that 404s,
    // which is worse than no documentation because it looks authoritative.
    const mounted = new Set(mountedRoutes().map(route => `${route.method} ${toTemplate(route.path)}`));
    const phantom = [...documentedOperations()].filter(operation => !mounted.has(operation));

    assert.deepEqual(phantom, [], `documented but not mounted:\n${phantom.join("\n")}`);
});

test("the document is OpenAPI 3.1 with the pieces a generator needs", () => {
    assert.equal(document.openapi, "3.1.0");
    assert.ok(document.info.title);
    assert.ok(document.info.version);
    assert.ok(document.servers.length > 0);
    assert.ok(document.components.securitySchemes.bearerAuth);
});

test("operation identifiers are present and unique", () => {
    const seen = new Set();
    for (const [path, methods] of Object.entries(document.paths)) {
        for (const [method, operation] of Object.entries(methods)) {
            const label = `${method.toUpperCase()} ${path}`;
            assert.ok(operation.operationId, `${label} has no operationId`);
            assert.equal(seen.has(operation.operationId), false, `${label} reuses operationId ${operation.operationId}`);
            seen.add(operation.operationId);
        }
    }
});

test("every $ref resolves to a declared schema", () => {
    const declared = new Set(Object.keys(document.components.schemas));
    const unresolved = [];

    (function walk(node, path) {
        if (node === null || typeof node !== "object") return;
        if (Array.isArray(node)) {
            node.forEach((entry, index) => walk(entry, `${path}[${index}]`));
            return;
        }
        for (const [key, value] of Object.entries(node)) {
            if (key === "$ref") {
                const name = String(value).replace("#/components/schemas/", "");
                if (!declared.has(name)) unresolved.push(`${path}: ${value}`);
            } else {
                walk(value, `${path}.${key}`);
            }
        }
    })(document, "document");

    assert.deepEqual(unresolved, []);
});

test("every operation declares a tag that the document also declares", () => {
    const declared = new Set(document.tags.map(tag => tag.name));
    for (const [path, methods] of Object.entries(document.paths)) {
        for (const [method, operation] of Object.entries(methods)) {
            assert.equal(operation.tags?.length, 1, `${method.toUpperCase()} ${path} should carry exactly one tag`);
            assert.ok(declared.has(operation.tags[0]), `${method.toUpperCase()} ${path} uses undeclared tag ${operation.tags[0]}`);
        }
    }
});

test("authenticated operations document a 401 and unauthenticated ones do not require a token", () => {
    for (const [path, methods] of Object.entries(document.paths)) {
        for (const [method, operation] of Object.entries(methods)) {
            const label = `${method.toUpperCase()} ${path}`;
            const requiresAuth = (operation.security ?? []).length > 0;
            if (requiresAuth) assert.ok(operation.responses["401"], `${label} needs a documented 401`);
        }
    }
});

test("every operation documents at least one success status", () => {
    for (const [path, methods] of Object.entries(document.paths)) {
        for (const [method, operation] of Object.entries(methods)) {
            const success = Object.keys(operation.responses).some(status => status.startsWith("2"));
            assert.ok(success, `${method.toUpperCase()} ${path} has no 2xx response`);
        }
    }
});

test("path templates and declared path parameters agree", () => {
    for (const [path, methods] of Object.entries(document.paths)) {
        const templated = [...path.matchAll(/\{([^}]+)\}/g)].map(match => match[1]);
        for (const [method, operation] of Object.entries(methods)) {
            const declared = (operation.parameters ?? []).filter(parameter => parameter.in === "path").map(parameter => parameter.name);
            assert.deepEqual(declared.sort(), [...templated].sort(), `${method.toUpperCase()} ${path} declares ${declared.join(",") || "no"} path parameters`);
        }
    }
});

test("the Postman collection is derived from the same document", () => {
    const collection = toPostmanCollection(document);
    const requests = collection.item.flatMap(folder => folder.item);

    assert.equal(
        requests.length,
        Object.values(document.paths).reduce((total, methods) => total + Object.keys(methods).length, 0),
        "every operation should appear exactly once"
    );
    assert.ok(collection.variable.some(variable => variable.key === "baseUrl"));
    assert.ok(collection.variable.some(variable => variable.key === "accessToken"));
    assert.ok(requests.every(request => request.request.url.raw.startsWith("{{baseUrl}}")));
});

test("authenticated Postman requests carry the bearer variable", () => {
    const collection = toPostmanCollection(document);
    const meRequest = collection.item
        .flatMap(folder => folder.item)
        .find(request => request.request.url.raw === "{{baseUrl}}/api/v1/auth/me" && request.request.method === "GET");

    assert.equal(meRequest.request.auth.type, "bearer");
    assert.equal(meRequest.request.auth.bearer[0].value, "{{accessToken}}");
});
