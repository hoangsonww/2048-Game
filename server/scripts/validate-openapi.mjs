#!/usr/bin/env node
/**
 * Structural validation of the OpenAPI document.
 *
 * This is not a full 3.1 validator; it checks the handful of properties that
 * have actually gone wrong when editing a spec by hand — a `$ref` pointing at
 * a schema that was renamed, an operation without an `operationId` (which
 * breaks every code generator), a duplicate `operationId`, a path with no
 * documented success response.
 */
import process from "node:process";
import { buildOpenApiDocument } from "../src/docs/openapi.js";

const document = buildOpenApiDocument({ serverUrl: "https://example.test" });
const problems = [];
const seenOperationIds = new Set();

function walkRefs(node, path) {
    if (node === null || typeof node !== "object") return;
    if (Array.isArray(node)) {
        node.forEach((entry, index) => walkRefs(entry, `${path}[${index}]`));
        return;
    }
    for (const [key, value] of Object.entries(node)) {
        if (key === "$ref" && typeof value === "string") {
            const name = value.replace("#/components/schemas/", "");
            if (!value.startsWith("#/components/schemas/") || !document.components.schemas[name]) {
                problems.push(`${path}: unresolvable $ref ${value}`);
            }
        } else {
            walkRefs(value, `${path}.${key}`);
        }
    }
}

if (document.openapi !== "3.1.0") problems.push(`Unexpected OpenAPI version: ${document.openapi}`);
if (!document.info?.title) problems.push("info.title is missing");
if (!document.info?.version) problems.push("info.version is missing");
if (!Array.isArray(document.servers) || document.servers.length === 0) problems.push("servers is empty");

const declaredTags = new Set(document.tags.map(tag => tag.name));

for (const [path, operations] of Object.entries(document.paths)) {
    if (!path.startsWith("/")) problems.push(`Path does not start with a slash: ${path}`);

    for (const [method, operation] of Object.entries(operations)) {
        const label = `${method.toUpperCase()} ${path}`;

        if (!operation.operationId) problems.push(`${label}: missing operationId`);
        else if (seenOperationIds.has(operation.operationId)) problems.push(`${label}: duplicate operationId ${operation.operationId}`);
        else seenOperationIds.add(operation.operationId);

        if (!operation.summary) problems.push(`${label}: missing summary`);

        for (const tag of operation.tags ?? []) {
            if (!declaredTags.has(tag)) problems.push(`${label}: uses undeclared tag ${tag}`);
        }

        const statuses = Object.keys(operation.responses ?? {});
        if (!statuses.some(status => status.startsWith("2"))) problems.push(`${label}: no 2xx response documented`);

        // Every path template parameter must be declared, or "Try it" in the
        // docs renders a URL with a literal `{id}` in it.
        for (const match of path.matchAll(/\{([^}]+)\}/g)) {
            const declared = (operation.parameters ?? []).some(parameter => parameter.in === "path" && parameter.name === match[1]);
            if (!declared) problems.push(`${label}: path parameter {${match[1]}} is not declared`);
        }
    }
}

walkRefs(document.paths, "paths");
walkRefs(document.components.schemas, "components.schemas");

if (problems.length > 0) {
    console.error(`OpenAPI document has ${problems.length} problem(s):`);
    console.error(problems.map(problem => `  - ${problem}`).join("\n"));
    process.exit(1);
}

const operationCount = Object.values(document.paths).reduce((total, operations) => total + Object.keys(operations).length, 0);
console.log(`OpenAPI 3.1 document is structurally valid: ${Object.keys(document.paths).length} paths, ${operationCount} operations, ${Object.keys(document.components.schemas).length} schemas.`);
