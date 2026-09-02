# Claude Code instructions

@AGENTS.md

Treat `AGENTS.md` as the repository source of truth. Reusable workflows are in `.agents/skills/`; Claude-compatible adapters in `.claude/skills/` point to the same instructions. Prefer `make` and `scripts/` entry points over inventing one-off commands.
