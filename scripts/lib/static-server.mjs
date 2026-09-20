import fs from "node:fs";
import http from "node:http";
import path from "node:path";

const contentTypes = {
    ".css": "text/css; charset=utf-8",
    ".html": "text/html; charset=utf-8",
    ".ico": "image/x-icon",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml; charset=utf-8",
    ".txt": "text/plain; charset=utf-8",
    ".webmanifest": "application/manifest+json; charset=utf-8",
    ".xml": "application/xml; charset=utf-8"
};

/**
 * @param {string} rootDirectory
 * @param {object} [options]
 * @param {string} [options.apiBaseUrl] Point the page's cloud client at a
 *   local API. Injected into the served HTML rather than committed to it, so
 *   the checked-in page always ships the production default. Local QA only.
 */
export function createStaticServer(rootDirectory, { apiBaseUrl } = {}) {
    const root = path.resolve(rootDirectory);

    return http.createServer((request, response) => {
        const requestURL = new URL(request.url ?? "/", "http://localhost");
        const decodedPath = decodeURIComponent(requestURL.pathname);
        const relativePath = decodedPath === "/" ? "index.html" : decodedPath.replace(/^\/+/, "");
        const candidate = path.resolve(root, relativePath);

        if (candidate !== root && !candidate.startsWith(`${root}${path.sep}`)) {
            response.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" }).end("Forbidden");
            return;
        }

        fs.stat(candidate, (error, stats) => {
            if (error || !stats.isFile()) {
                response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" }).end("Not found");
                return;
            }

            const type = contentTypes[path.extname(candidate).toLowerCase()] ?? "application/octet-stream";
            const headers = {
                "Cache-Control": "no-store",
                "Content-Type": type,
                "X-Content-Type-Options": "nosniff"
            };

            if (apiBaseUrl && type.startsWith("text/html")) {
                fs.readFile(candidate, "utf8", (readError, html) => {
                    if (readError) {
                        response.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" }).end("Read failed");
                        return;
                    }
                    const injected = html.replace(
                        "</head>",
                        `<script>window.GAME2048_API_BASE_URL = ${JSON.stringify(apiBaseUrl)};</script></head>`
                    );
                    response.writeHead(200, headers).end(injected);
                });
                return;
            }

            response.writeHead(200, headers);
            fs.createReadStream(candidate).pipe(response);
        });
    });
}
