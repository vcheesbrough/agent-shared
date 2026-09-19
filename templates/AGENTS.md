# Agent guide — <REPO>

This file holds the **<REPO>-specific** working rules. The machine-global rules
common to every repo — Kanban/bored workflow, iteration & versioning defaults,
branching & git safety, CI-after-push, PR self-review + comment loop, test
coverage, and MCP/secrets discipline — live in the shared **agent-shared
baseline**, imported on this machine via `~/.codex/AGENTS.md` and
`~/.claude/CLAUDE.md` (run `agent-shared/install.sh` once per machine to wire
this up). **Read that baseline first;** this file only records what is specific
to <REPO> or overrides the baseline.

If you change a <REPO> rule, change it here — there is no parallel copy.
Cross-repo rules change in `agent-shared`, not here.

---

## Repository context

| Item | Value |
| --- | --- |
| **Remote / `gh` repo** | `<owner>/<repo>` |
| **Trunk** | `<main|master>` |
| **Kanban board** | `https://bored.desync.link/boards/<slug>` |
| **Phase** | `<pre-MVP 0.N.P | post-MVP 1.N.P>` |

Shared skills apply here once the machine is wired up (`start-iteration`,
`ci-watch`, `pr-review-loop`). Their per-repo parameters:

- `OWNER=<owner>`, `REPO=<repo>`
- CI reproduce commands: `<repo-specific docker/compose commands, or delete>`
- Extra review criteria beyond the baseline five (correctness, security/OWASP,
  tests, versioning, scope): `<repo-specific checks, or delete if none>`

---

## Repo-specific rules

<!--
Add only what is NOT already in the baseline. Examples of genuinely
repo-specific content:
  - deployment / smoke-test procedure and commands
  - post-pipeline checks (e.g. a live endpoint version probe)
  - launcher scripts, custom target dirs, tool-specific helpers
  - overrides of a baseline default (state which baseline section you override)
  - a bootstrap exception, a plan/spec pointer, a scope gate
Delete this comment when you add real content.
-->
