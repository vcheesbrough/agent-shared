# agent-shared

Shared agent-configuration repository. Holds the canonical, cross-repo
baseline and portable Agent Skills used by both **Codex** and **Claude
Code** on this machine.

## Layout

```
agent-shared/
├── README.md
├── global/
│   └── AGENTS.md            # canonical cross-repo baseline (see below)
└── skills/
    └── pr-review-loop/
        └── SKILL.md         # portable Agent Skill (core spec only)
```

## How it's wired up

Files here are the single source of truth. The agent tools consume them
via symlinks on this machine:

| Symlink                              | Target                              |
| ------------------------------------ | ----------------------------------- |
| `~/.codex/AGENTS.md`                 | `global/AGENTS.md`                  |
| `~/.claude/CLAUDE.md`                | `global/AGENTS.md`                  |
| `~/.claude/skills/pr-review-loop`    | `skills/pr-review-loop`             |
| `~/.agents/skills/pr-review-loop`    | `skills/pr-review-loop`             |

Edit the files in this repo; the symlinks pick up changes automatically.
Each new skill under `skills/` gets the same pair of symlinks
(`~/.claude/skills/<name>` and `~/.agents/skills/<name>`).

## Conventions

- `global/AGENTS.md` is the canonical baseline imported everywhere.
- Skills under `skills/` stay portable: keep `SKILL.md` frontmatter to
  the core Agent Skills spec (`name`, `description`) so they work in both
  Codex and Claude Code.
