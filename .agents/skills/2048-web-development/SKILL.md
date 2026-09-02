---
name: 2048-web-development
description: Implement or review the 2048 browser client, including its rules engine, responsive UI, accessibility, PWA metadata, screenshots, or SEO.
---

# 2048 web development

Read `AGENTS.md` and `docs/architecture.md`. Keep rules in `Web-Version/game-engine.js` deterministic and DOM/storage concerns in `Web-Version/script.js`. The app must remain static and work beneath the GitHub Pages `/2048-Game/` base path.

For controls, use inline SVG with a `viewBox`, center it through layout, and put the accessible name on the button. Preserve keyboard arrows, WASD, touch swipes, mobile direction buttons, undo, restart confirmation, state recovery, win continuation, and game-over restart.

A board swipe must not scroll the page. The board sets `touch-action: none`, `html`/`body` set `overscroll-behavior: none`, and a non-passive `touchmove` listener scoped to the board calls `preventDefault()` — the other touch listeners are passive and cannot. Keep the `touchcancel` handler that clears the start point, and keep scrolling working for gestures that begin anywhere else.

When changing public content or routes, update canonical/social metadata, JSON-LD, sitemap, robots, manifest, and `llms*.txt` where relevant. Do not add claims or structured data that are not visible and true on the page.

Run `make check` and `make test-web`. For visible changes, run `make screenshots-web` and inspect desktop and mobile gameplay, restart, win, loss, and About captures.
