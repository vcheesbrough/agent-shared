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
│   ├── start-iteration/     # start a bored card as a numbered iteration
│   └── api-versioning/      # design knowledge: remote API version contract
├── agents/                  # subagent definitions (Claude Code only)
│   ├── pr-self-review.md    # reviews a PR diff in a clean context
│   └── ci-diagnose.md       # reads failed CI logs, returns a short diagnosis
├── hooks/                   # hook scripts referenced from settings.json
│   └── gh-pr-create-selfreview.py
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
| `~/.claude/agents/<name>.md`         | `agents/<name>.md`                  |

Edit the files in this repo; the symlinks pick up changes automatically.
Every skill under `skills/` gets the same pair of symlinks
(`~/.claude/skills/<name>` and `~/.agents/skills/<name>`) — currently
`pr-review-loop`, `ci-watch`, `start-iteration`, and `api-versioning`.

## Skills: procedures and design knowledge

Skills here come in two kinds. **Procedure skills** (`start-iteration`,
`ci-watch`, `pr-review-loop`) package a workflow the baseline mandates.
**Topic skills** (`api-versioning`) record a design decision worked out in one
repo so every other repo starts from it: the rule, why it holds, and when it
does not apply.

Design knowledge goes in a topic skill rather than in `global/AGENTS.md`
because the baseline is loaded in full by every session in every repo, while a
skill costs one description line until its topic comes up. Keep `SKILL.md` to
what is needed whenever the topic is touched, and move rarely-needed procedures
into `references/` beside it. Each topic skill gets one pointer line in
baseline §10 so it triggers reliably, stays language-agnostic, and names the
repo that is its worked example instead of copying that repo's code.

## Agents

`agents/` holds subagent definitions. Unlike skills these are **Claude
Code-only** (Codex has no equivalent), so they get a single link into
`~/.claude/agents/`.

Subagents earn their keep in two distinct ways here.

**A clean context** — work that must happen *without* the conversation that led
up to it. `pr-self-review` is the case: baseline §5 requires every PR to be
self-reviewed, but the agent that wrote the branch already believes it is
correct. The subagent sees the repo and the diff and nothing else, so it reviews
the code rather than re-endorsing the author's reasoning. The `pr-review-loop`
skill spawns it in Part A and passes coordinates only — owner, repo, PR number,
trunk — deliberately withholding the design rationale.

**A throwaway context** — work that reads a lot, returns a little, and never
needs its intermediates again. `ci-diagnose` is the case: a failing Woodpecker
step can run to tens of thousands of log lines, and once those land in the main
context they sit there for the rest of the iteration, crowding out the actual
work. The subagent reads them, returns ~20 lines of diagnosis, and the logs die
with it. It runs on Sonnet — log triage does not need the main thread's model,
and per-agent `model:` frontmatter is the cheapest lever in the whole setup.

Not everything is worth delegating. `start-iteration` is a handful of MCP calls
returning small payloads; spawning a subagent costs more than it saves. Nor can
the §5 Part B triage loop be delegated at all — it needs a user decision per
comment. The test is: does it read a lot, return a little, and never need its
intermediates again?

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

## Hooks

`hooks/` holds hook scripts kept under version control here and referenced by
absolute path from `~/.claude/settings.json`. `install.sh` does **not** wire
them up — merging into a settings file that carries unrelated machine-specific
keys is not something a symlink can do safely — so each is added once by hand.
Every script's docstring carries the settings block to paste.

Currently `gh-pr-create-selfreview.py` (`PostToolUse` on `Bash`): it watches for
a successful `gh pr create` and feeds baseline §5 back into the transcript with
the new PR number, at the one moment the rule applies and is easiest to skip.

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
`AGENTS.md` with the repo's own `OWNER`/`REPO`/reproduce parameters.

## Conventions

- `global/AGENTS.md` is the canonical baseline imported everywhere.
- Skills under `skills/` stay portable: keep `SKILL.md` frontmatter to
  the core Agent Skills spec (`name`, `description`) so they work in both
  Codex and Claude Code.
