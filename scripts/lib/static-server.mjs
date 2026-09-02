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

export function createStaticServer(rootDirectory) {
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

            response.writeHead(200, {
                "Cache-Control": "no-store",
                "Content-Type": contentTypes[path.extname(candidate).toLowerCase()] ?? "application/octet-stream",
                "X-Content-Type-Options": "nosniff"
            });
            fs.createReadStream(candidate).pipe(response);
        });
    });
}
