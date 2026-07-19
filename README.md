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
    └── example-skill/
        └── SKILL.md         # portable Agent Skill (core spec only)
```

## How it's wired up

Files here are the single source of truth. The agent tools consume them
via symlinks on this machine:

| Symlink                              | Target                              |
| ------------------------------------ | ----------------------------------- |
| `~/.codex/AGENTS.md`                 | `global/AGENTS.md`                  |
| `~/.claude/CLAUDE.md`                | `global/AGENTS.md`                  |
| `~/.claude/skills/example-skill`     | `skills/example-skill`              |
| `~/.agents/skills/example-skill`     | `skills/example-skill`              |

Edit the files in this repo; the symlinks pick up changes automatically.

## Conventions

- `global/AGENTS.md` is the canonical baseline imported everywhere.
- Skills under `skills/` stay portable: keep `SKILL.md` frontmatter to
  the core Agent Skills spec (`name`, `description`) so they work in both
  Codex and Claude Code.
