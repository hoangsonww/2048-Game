#!/usr/bin/env node
/**
 * Writes the Postman collection to disk, derived from the same OpenAPI
 * document the API serves. Nothing about the collection is hand-maintained,
 * which is what keeps it from drifting away from the spec.
 */
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { buildOpenApiDocument } from "../src/docs/openapi.js";
import { toPostmanCollection } from "../src/docs/ui.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outputDirectory = process.argv[2] ? path.resolve(process.argv[2]) : path.join(root, "openapi");
fs.mkdirSync(outputDirectory, { recursive: true });

const collection = toPostmanCollection(buildOpenApiDocument({ serverUrl: process.env.PUBLIC_URL ?? "https://example.test" }));
const target = path.join(outputDirectory, "2048-cloud-api.postman_collection.json");
fs.writeFileSync(target, `${JSON.stringify(collection, null, 2)}\n`);

console.log(`Wrote ${path.relative(process.cwd(), target)} with ${collection.item.length} folders.`);
