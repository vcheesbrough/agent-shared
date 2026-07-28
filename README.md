# agent-shared

Shared agent-configuration repository. Holds the canonical, cross-repo
baseline and portable Agent Skills used by both **Codex** and **Claude
Code** on this machine.

## Layout

```
agent-shared/
├── README.md
├── install.sh               # one-command machine setup (idempotent)
├── global/
│   └── AGENTS.md            # canonical cross-repo baseline (see below)
├── skills/                  # portable Agent Skills (core spec only)
│   ├── pr-review-loop/       # self-review a PR, then resolve threads
│   ├── ci-watch/            # monitor CI to completion, reproduce failures
│   └── start-iteration/     # start a bored card as a numbered iteration
└── templates/               # starting points for a new repo
    ├── AGENTS.md            # repo-delta guide (fill in the placeholders)
    └── CLAUDE.md            # one-line pointer to AGENTS.md
```

## How it's wired up

Files here are the single source of truth. The agent tools consume them
via symlinks on this machine:

| Symlink                              | Target                              |
| ------------------------------------ | ----------------------------------- |
| `~/.codex/AGENTS.md`                 | `global/AGENTS.md`                  |
| `~/.claude/CLAUDE.md`                | `global/AGENTS.md`                  |
| `~/.claude/skills/<name>`            | `skills/<name>`                     |
| `~/.agents/skills/<name>`            | `skills/<name>`                     |

Edit the files in this repo; the symlinks pick up changes automatically.
Every skill under `skills/` gets the same pair of symlinks
(`~/.claude/skills/<name>` and `~/.agents/skills/<name>`) — currently
`pr-review-loop`, `ci-watch`, and `start-iteration`.

## Set up on a new machine

Clone this repo, then run the installer — it creates every symlink above
idempotently (backs up any real file in the way to `.bak-<timestamp>`,
leaves correct links alone, prunes dangling skill links):

```bash
git clone <this-repo-url> ~/dev/agent-shared
~/dev/agent-shared/install.sh          # or --dry-run to preview
```

Re-run `install.sh` any time you add a skill or set up a new machine — it is
safe to run repeatedly. Because the skills install as **personal** skills
(`~/.claude/skills`, `~/.agents/skills`), they are available in **every** repo
on the machine; no per-repo symlink is needed (and none should be committed —
the target path is machine-specific).

## Onboard a new repo

A repo joins this infrastructure by carrying a thin, repo-specific `AGENTS.md`
that defers to the baseline. From the new repo root:

```bash
cp ~/dev/agent-shared/templates/AGENTS.md ./AGENTS.md
cp ~/dev/agent-shared/templates/CLAUDE.md ./CLAUDE.md
```

Then fill in the placeholders in `AGENTS.md` (repo, trunk, board slug, phase,
skill parameters) and delete anything the baseline already covers. The shared
skills (`start-iteration`, `ci-watch`, `pr-review-loop`) work automatically once
the machine has been set up above — reference them by name from the repo's
`AGENTS.md` with the repo's own `OWNER`/`REPO`/rubric/reproduce parameters.

## Conventions

- `global/AGENTS.md` is the canonical baseline imported everywhere.
- Skills under `skills/` stay portable: keep `SKILL.md` frontmatter to
  the core Agent Skills spec (`name`, `description`) so they work in both
  Codex and Claude Code.
