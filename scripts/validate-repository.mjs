#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const failures = [];
const requiredFiles = [
    ".devcontainer/devcontainer.json",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/dependabot.yml",
    ".pre-commit-config.yaml",
    "AGENTS.md",
    "CLAUDE.md",
    "Makefile",
    "llms.txt",
    "llms-full.txt",
    "manifest.json",
    "robots.txt",
    "sitemap.xml"
];

function read(relativePath) {
    return fs.readFileSync(path.join(root, relativePath), "utf8");
}

function check(condition, message) {
    if (!condition) failures.push(message);
}

for (const relativePath of requiredFiles) {
    check(fs.existsSync(path.join(root, relativePath)), `Missing required file: ${relativePath}`);
}

for (const relativePath of ["package.json", "manifest.json", ".devcontainer/devcontainer.json"]) {
    try {
        JSON.parse(read(relativePath));
    } catch (error) {
        failures.push(`Invalid JSON in ${relativePath}: ${error.message}`);
    }
}

const packageJSON = JSON.parse(read("package.json"));
for (const script of ["check", "test", "test:browser", "test:unit", "screenshots:web", "prepare"]) {
    check(Boolean(packageJSON.scripts?.[script]), `package.json is missing script: ${script}`);
}

for (const page of ["index.html", "Web-Version/about.html"]) {
    const html = read(page);
    check(/<html\s+lang="en"/.test(html), `${page} must declare its language`);
    check(/<title>[^<]{10,65}<\/title>/.test(html), `${page} needs a descriptive title`);
    check(/name="description"\s+content="[^"]{80,170}"/.test(html), `${page} needs an 80–170 character description`);
    check(/rel="canonical"\s+href="https:\/\//.test(html), `${page} needs an absolute canonical URL`);
    check(/property="og:image"/.test(html), `${page} needs an Open Graph image`);
    check(/name="twitter:card"/.test(html), `${page} needs Twitter card metadata`);

    for (const match of html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
        try {
            JSON.parse(match[1]);
        } catch (error) {
            failures.push(`${page} contains invalid JSON-LD: ${error.message}`);
        }
    }
}

const sitemap = read("sitemap.xml");
for (const expectedURL of [
    "https://hoangsonww.github.io/2048-Game/",
    "https://hoangsonww.github.io/2048-Game/Web-Version/about.html"
]) {
    check(sitemap.includes(`<loc>${expectedURL}</loc>`), `Sitemap is missing ${expectedURL}`);
}

const robots = read("robots.txt");
check(robots.includes("Sitemap: https://hoangsonww.github.io/2048-Game/sitemap.xml"), "robots.txt must advertise the canonical sitemap");

const llms = read("llms.txt");
for (const requiredLink of ["/2048-Game/", "/2048-Game/Web-Version/about.html", "/2048-Game/llms-full.txt"]) {
    check(llms.includes(requiredLink), `llms.txt is missing ${requiredLink}`);
}

if (failures.length > 0) {
    console.error(failures.map(failure => `- ${failure}`).join("\n"));
    process.exit(1);
}

console.log("Repository structure, JSON, SEO metadata, and discovery files are valid.");
