#!/usr/bin/env node
/**
 * Writes the OpenAPI document to disk as JSON and YAML.
 *
 * The API serves both at runtime; this exists for the cases a running server
 * cannot cover — diffing the contract in a pull request, feeding a client
 * generator in CI, or publishing the spec alongside a release.
 */
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import yaml from "js-yaml";
import { buildOpenApiDocument } from "../src/docs/openapi.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outputDirectory = process.argv[2] ? path.resolve(process.argv[2]) : path.join(root, "openapi");
const serverUrl = process.env.PUBLIC_URL ?? "https://example.test";

fs.mkdirSync(outputDirectory, { recursive: true });

const document = buildOpenApiDocument({ serverUrl });
fs.writeFileSync(path.join(outputDirectory, "openapi.json"), `${JSON.stringify(document, null, 2)}\n`);
fs.writeFileSync(path.join(outputDirectory, "openapi.yaml"), yaml.dump(document, { noRefs: true, lineWidth: 120 }));

console.log(`Wrote openapi.json and openapi.yaml to ${path.relative(process.cwd(), outputDirectory)}`);
