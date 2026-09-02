# Serves the 2048 web client.
#
# The web app is static — no bundler, no framework, no runtime dependencies.
# `package.json` lists only devDependencies (c8, husky, playwright), so this
# image installs nothing from npm: it is the Node runtime, the static files,
# and the same `scripts/serve-web.mjs` that `make serve` runs locally. That
# keeps what ships identical to what contributors test.
#
#   docker build -t 2048-game .
#   docker run --rm -p 8080:8080 2048-game
#
# The iOS and Android clients are not in here. Both need vendor toolchains
# that cannot run in this image, and neither is a server.

FROM node:22-bookworm-slim

# Tini reaps zombies and forwards signals, so `docker stop` reaches the
# server's own SIGTERM handler instead of being papered over by a PID 1 that
# ignores it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copied as separate layers so an edit to the game does not invalidate the
# server, and vice versa. `serve-web.mjs` resolves its document root as the
# parent of `scripts/`, which is why the layout below mirrors the repository.
COPY scripts/serve-web.mjs ./scripts/serve-web.mjs
COPY scripts/lib/ ./scripts/lib/
COPY images/ ./images/
COPY Web-Version/ ./Web-Version/
COPY index.html 404.html manifest.json robots.txt sitemap.xml humans.txt llms.txt llms-full.txt ./

ENV NODE_ENV=production \
    PORT=8080

EXPOSE 8080

# The base image ships an unprivileged `node` user. Nothing here needs root,
# and the served tree is read-only to the process.
USER node

# Node 22 has a global fetch, so this needs no extra package.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 8080) + '/').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "scripts/serve-web.mjs"]
