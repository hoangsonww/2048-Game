/**
 * Documentation surfaces: Swagger UI, Redoc, Scalar, raw JSON, raw YAML, and a
 * generated Postman collection.
 *
 * Every renderer is loaded from a pinned CDN build rather than from an npm
 * package served by the app. `swagger-ui-express` ships a directory of static
 * assets, and a serverless function that has to serve a static directory is a
 * class of deployment bug — wrong base path, missing file, 404 on a stylesheet
 * — that buys nothing here. One HTML string per renderer has no such failure
 * mode, and pinning the version means the page cannot change under us.
 */
import express from "express";
import yaml from "js-yaml";
import { buildOpenApiDocument } from "./openapi.js";
import config from "../config/env.js";

const SWAGGER_VERSION = "5.20.1";
const REDOC_VERSION = "2.2.0";
const SCALAR_VERSION = "1.25.122";

const router = express.Router();

function documentFor(req) {
    // The server URL is derived from the request so the "Try it" button works
    // on a preview deployment, a custom domain, and localhost without three
    // different builds.
    const proto = req.get("x-forwarded-proto") ?? req.protocol;
    const host = req.get("x-forwarded-host") ?? req.get("host");
    return buildOpenApiDocument({ serverUrl: host ? `${proto}://${host}` : config.publicUrl });
}

const SHELL_STYLE = `
  :root { color-scheme: light; }
  body { margin: 0; font-family: "Outfit", ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; background: #f5f0e6; color: #24231f; }
  .docs-bar { display: flex; gap: 1.25rem; align-items: center; padding: 0.75rem 1.25rem; background: #24231f; color: #f5f0e6; font-size: 0.9rem; }
  .docs-bar strong { font-weight: 700; letter-spacing: 0.01em; }
  .docs-bar a { color: #f5f0e6; text-decoration: none; opacity: 0.75; }
  .docs-bar a:hover, .docs-bar a:focus-visible { opacity: 1; text-decoration: underline; }
  .docs-bar a[aria-current="page"] { opacity: 1; color: #e96345; }
  .docs-bar .spacer { margin-left: auto; }
`;

function shell(current) {
    const link = (href, label) => `<a href="${href}"${href === current ? ' aria-current="page"' : ""}>${label}</a>`;
    return `<nav class="docs-bar" aria-label="API documentation">
      <strong>2048 Cloud API</strong>
      ${link("/docs", "Swagger UI")}
      ${link("/redoc", "Redoc")}
      ${link("/reference", "Scalar")}
      <span class="spacer"></span>
      ${link("/openapi.json", "openapi.json")}
      ${link("/openapi.yaml", "openapi.yaml")}
      ${link("/postman.json", "Postman")}
    </nav>`;
}

router.get("/openapi.json", (req, res) => {
    res.set("Cache-Control", "public, max-age=0, s-maxage=300").json(documentFor(req));
});

router.get("/openapi.yaml", (req, res) => {
    res
        .set("Cache-Control", "public, max-age=0, s-maxage=300")
        .type("application/yaml")
        .send(yaml.dump(documentFor(req), { noRefs: true, lineWidth: 120 }));
});

router.get("/docs", (req, res) => {
    res.type("html").send(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>2048 Cloud API — Swagger UI</title>
<meta name="description" content="Interactive reference for the 2048 Cloud API: accounts, cross-device saves, leaderboards, achievements, and statistics.">
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@${SWAGGER_VERSION}/swagger-ui.css">
<link rel="icon" href="https://hoangsonww.github.io/2048-Game/images/favicon.svg" type="image/svg+xml">
<style>${SHELL_STYLE} .swagger-ui .topbar { display: none; }</style>
</head>
<body>
${shell("/docs")}
<div id="swagger"></div>
<script src="https://unpkg.com/swagger-ui-dist@${SWAGGER_VERSION}/swagger-ui-bundle.js" crossorigin></script>
<script src="https://unpkg.com/swagger-ui-dist@${SWAGGER_VERSION}/swagger-ui-standalone-preset.js" crossorigin></script>
<script>
  window.ui = SwaggerUIBundle({
    url: "/openapi.json",
    dom_id: "#swagger",
    deepLinking: true,
    persistAuthorization: true,
    displayRequestDuration: true,
    filter: true,
    tryItOutEnabled: true,
    defaultModelsExpandDepth: 1,
    docExpansion: "list",
    presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],
    plugins: [SwaggerUIBundle.plugins.DownloadUrl],
    layout: "BaseLayout"
  });
</script>
</body>
</html>`);
});

router.get("/redoc", (req, res) => {
    res.type("html").send(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>2048 Cloud API — Redoc</title>
<meta name="description" content="Three-panel reference for the 2048 Cloud API: accounts, cross-device saves, leaderboards, achievements, and statistics.">
<link rel="icon" href="https://hoangsonww.github.io/2048-Game/images/favicon.svg" type="image/svg+xml">
<style>${SHELL_STYLE}</style>
</head>
<body>
${shell("/redoc")}
<div id="redoc"></div>
<script src="https://cdn.redoc.ly/redoc/v${REDOC_VERSION}/bundles/redoc.standalone.js" crossorigin></script>
<script>
  Redoc.init("/openapi.json", {
    hideDownloadButton: false,
    expandResponses: "200,201",
    jsonSampleExpandLevel: 3,
    pathInMiddlePanel: true,
    theme: {
      colors: { primary: { main: "#e96345" }, text: { primary: "#24231f", secondary: "#6f6a61" } },
      typography: {
        fontFamily: '"Outfit", ui-sans-serif, system-ui, sans-serif',
        code: { fontFamily: '"DM Mono", ui-monospace, monospace' },
        headings: { fontFamily: '"Outfit", ui-sans-serif, system-ui, sans-serif', fontWeight: "700" }
      },
      sidebar: { backgroundColor: "#f1e8d9", textColor: "#24231f" }
    }
  }, document.getElementById("redoc"));
</script>
</body>
</html>`);
});

router.get("/reference", (req, res) => {
    res.type("html").send(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>2048 Cloud API — Reference</title>
<meta name="description" content="Searchable API reference with generated client snippets for the 2048 Cloud API.">
<link rel="icon" href="https://hoangsonww.github.io/2048-Game/images/favicon.svg" type="image/svg+xml">
<style>${SHELL_STYLE}</style>
</head>
<body>
${shell("/reference")}
<script id="api-reference" data-url="/openapi.json"></script>
<script>
  var configuration = { theme: "default", layout: "modern", hideDownloadButton: false, searchHotKey: "k" };
  document.getElementById("api-reference").dataset.configuration = JSON.stringify(configuration);
</script>
<script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference@${SCALAR_VERSION}/dist/browser/standalone.min.js" crossorigin></script>
</body>
</html>`);
});

/**
 * A Postman collection generated from the same document.
 *
 * Hand-maintaining a second description of the API is how the two drift; this
 * is derived, so it cannot.
 */
export function toPostmanCollection(document) {
    const folders = new Map();

    for (const [path, operations] of Object.entries(document.paths)) {
        for (const [method, operation] of Object.entries(operations)) {
            const tag = operation.tags?.[0] ?? "Other";
            if (!folders.has(tag)) folders.set(tag, []);

            const queryParams = (operation.parameters ?? [])
                .filter(parameter => parameter.in === "query")
                .map(parameter => ({
                    key: parameter.name,
                    value: parameter.schema?.default === undefined ? "" : String(parameter.schema.default),
                    description: parameter.description,
                    disabled: parameter.schema?.default === undefined
                }));

            folders.get(tag).push({
                name: operation.summary ?? `${method.toUpperCase()} ${path}`,
                request: {
                    method: method.toUpperCase(),
                    description: operation.description ?? operation.summary,
                    header: [
                        { key: "Content-Type", value: "application/json" },
                        { key: "X-Client", value: "cli" }
                    ],
                    ...(operation.requestBody
                        ? { body: { mode: "raw", raw: "{}", options: { raw: { language: "json" } } } }
                        : {}),
                    url: {
                        raw: `{{baseUrl}}${path}`,
                        host: ["{{baseUrl}}"],
                        path: path.split("/").filter(Boolean),
                        query: queryParams
                    },
                    auth: operation.security?.length ? { type: "bearer", bearer: [{ key: "token", value: "{{accessToken}}" }] } : undefined
                }
            });
        }
    }

    return {
        info: {
            name: `${document.info.title} v${document.info.version}`,
            description: document.info.summary,
            schema: "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        variable: [
            { key: "baseUrl", value: document.servers[0].url },
            { key: "accessToken", value: "" }
        ],
        item: [...folders.entries()].map(([name, items]) => ({ name, item: items }))
    };
}

router.get("/postman.json", (req, res) => {
    res
        .set("Content-Disposition", 'attachment; filename="2048-cloud-api.postman_collection.json"')
        .json(toPostmanCollection(documentFor(req)));
});

export default router;
