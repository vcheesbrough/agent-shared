# Agent guide — agent-shared

This file holds the **agent-shared-specific** working rules. The machine-global
rules common to every repo — Kanban/bored workflow, iteration & versioning
defaults, branching & git safety, CI-after-push, PR self-review + comment loop,
test coverage, and MCP/secrets discipline — live in the shared **agent-shared
baseline** at [`global/AGENTS.md`](global/AGENTS.md), imported on this machine
via `~/.codex/AGENTS.md` and `~/.claude/CLAUDE.md` (run [`install.sh`](install.sh)
once per machine to wire this up). **Read that baseline first;** this file only
records what is specific to this repo or overrides the baseline.

Note the double role: this repo *authors* the baseline every other repo reads,
and it is also a repo an agent works in. `global/AGENTS.md` is the rules for
everywhere else; **this** file is the rules for here.

If you change an agent-shared rule, change it here — there is no parallel copy.

---

## Repository context

| Item | Value |
| --- | --- |
| **Remote / `gh` repo** | `vcheesbrough/agent-shared` |
| **Trunk** | `main` |
| **CI** | none — no Woodpecker or GitHub Actions config in this repo |
| **Kanban board** | none — work here is not tracked on a bored board |

Contents: `global/AGENTS.md` (the cross-repo baseline), `skills/` and `agents/`
(shared skills and subagents), `templates/` (the `AGENTS.md` / `CLAUDE.md` pair
a new repo starts from), `hooks/`, and `install.sh`.

---

## Repo-specific rules

### Commit directly to `main` — no feature branches

**Overrides baseline §3 (branching & git safety) for this repo only.** Do not
create a feature branch, do not open a PR: commit the change on `main` and push.

This repo holds prose rules, skills and templates rather than shipping product
code. There is no CI to gate a merge on and no build to break, so the
branch-plus-PR ceremony adds a round trip without adding a check. Everywhere
else, baseline §3 still stands.

What carries over from the baseline unchanged:

- **Ask before committing** unless the user has asked for the change. The
  override removes the branch, not the user's say-so over what lands.
- **Never force-push `main`**, and no history rewrites (`reset --hard`,
  `push --force`) without an explicit request.
- Commit messages still follow baseline §8 (Conventional Commits).

Consequences of no branch: there is no PR, so the `pr-review-loop` skill has
nothing to run against here, and `start-iteration`'s branch/semver mapping
(baseline §2) does not apply — this repo carries no version number.

> A machine-global `UserPromptSubmit` hook in `~/.claude/settings.json` injects
> a "always create a feature branch first" rule into every prompt in every
> project. In this repo that hook is **wrong** and this section wins. Fix the
> hook to exempt this repo if the reminder becomes noise.
