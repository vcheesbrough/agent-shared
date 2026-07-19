# AGENTS.md — Canonical Cross-Repo Baseline

> This file is the **canonical, cross-repo baseline** for agent behavior on
> this machine. It is the single source of truth, imported by both **Codex**
> and **Claude Code** via symlinks (`~/.codex/AGENTS.md` and
> `~/.claude/CLAUDE.md` both point here). Edit it here; every tool picks up
> the change. Repo-specific instructions live in each project's own
> `AGENTS.md` / `CLAUDE.md` and take precedence over this baseline.

## Commit message conventions

<!-- Placeholder — replace with your real conventions. -->

- Use [Conventional Commits](https://www.conventionalcommits.org/):
  `type(scope): summary`, e.g. `feat(auth): add token refresh`.
- Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`.
- Keep the subject line in the imperative mood and under ~72 characters.
- Explain the *why* in the body when the change isn't self-evident.

## General code style

<!-- Placeholder — replace with your real preferences. -->

- Match the style of the surrounding code; consistency beats personal taste.
- Prefer clear names over comments; comment the *why*, not the *what*.
- Keep functions small and single-purpose; avoid needless abstraction.
- Handle errors explicitly; don't swallow them silently.
- Format with the project's configured formatter/linter before committing.

## Notes

<!-- Add cross-cutting guidance that should apply to every repo here. -->
