# AGENTS.md — Canonical Cross-Repo Baseline

> This file is the **canonical, cross-repo baseline** for AI agents on this
> machine. It is the single source of truth for working rules that apply to
> **every** repo, imported by both **Codex** (`~/.codex/AGENTS.md`) and
> **Claude Code** (`~/.claude/CLAUDE.md`) via symlinks into this repo. Edit it
> here; every tool picks up the change.
>
> **Precedence:** a repository's own `AGENTS.md` is the source of truth for that
> repo and **overrides or extends** this baseline. Where a repo is silent, this
> baseline applies. In a repo, a `CLAUDE.md` should be a one-line pointer to
> that repo's `AGENTS.md`, not a parallel copy of rules.
>
> These rules are distilled from the working-rules layer shared by the
> `bored`, `sovereign-config`, and `v-note` repos (and, where applicable, the
> `mini-config` homelab repo). Repo-specific mechanics — iteration/semver
> numbering, board slugs, launcher scripts, deploy/smoke-test commands — stay
> in the individual repos, not here.

---

## 1. Kanban task queue (bored)

When a repo uses **bored** Kanban cards as its task queue:

- **One card at a time** unless the user explicitly says otherwise. No parallel
  cards, no stacking work.
- **Use bored MCP for all board/column/card reads and writes** (`list_boards`,
  `list_columns`, `list_cards`, `get_card_by_number`, `create_card`,
  `update_card`, `move_card`, …). **Do not** hit the bored HTTP API with `curl`
  or ad-hoc clients unless MCP is broken — then say so once, fall back
  minimally, and still obey these rules.
- **Default endpoint** `https://bored.desync.link`, scope `bored:prod:access`,
  unless the user instructs otherwise.
- **Move to In Progress** when you pick a card up; **move to Done** only after
  its PR is merged.
- **Keep the card aligned with reality:** compare the card body to the current
  source tree, replan if scope drifted, and `update_card` so acceptance, files,
  and out-of-scope notes stay accurate.
- **Cards have no separate title field** — the board shows the first markdown
  `#` heading in the body. The `Iteration N` heading convention (§2) applies to
  that first heading.

> Repo-specific: the board slug/URL lives in each repo's own `AGENTS.md`. The
> default iteration/branch/semver mapping is §2 below.

## 2. Iterations, branches & versioning (default)

This is the **default** convention for repos that ship product code in
numbered iterations (e.g. the Rust-app repos). A repo may **override** it — for
example, `mini-config` names branches after the card (`feat/<slug>`) with no
iteration heading or semver coupling.

> The kickoff sequence is packaged as the **`start-iteration`** skill (in
> `agent-shared/skills/`). Invoke that skill to start a card; the rules below
> are its canonical description.

- **One iteration = one bored card = one feature branch = one semver minor.**
  Do not split an iteration across cards or branches, and do not stack.
- **Assign `N` only when work starts.** The moment a card moves to In Progress,
  it takes the next iteration number `N` — sequential, `highest existing N + 1`
  across Done + In Progress cards (or `1` if none exist).
- **On In Progress**, `update_card` so:
  1. the first `#` heading becomes `# Iteration N — <description>` (one prefix,
     keep the descriptive title after the em dash);
  2. the body records **Branch:** `feat/iteration-N-short-slug` (from trunk);
  3. the body records the workspace **Version** (see below) once a version file
     exists.
- **Branch** `feat/iteration-N-short-slug` from trunk, created only after `N` is
  fixed. Never branch from another feature branch.
- **Versioning — major signals the MVP milestone, minor tracks the iteration:**
  - **Pre-MVP** (`0.x.x`, before the MVP lands on trunk): `0.N.P` — iteration 1
    → `0.1.0`, iteration 5 → `0.5.0`. A `0.x.x` version means the product has
    not yet reached its MVP.
  - **MVP release:** when the MVP-completion card merges to trunk, set the
    workspace to `1.0.0` and tag it. Crossing to `1.0.0` **is** the MVP
    milestone.
  - **Post-MVP** (`1.x.x`): `1.N.P`, with `N` **continuing** from the last
    pre-MVP iteration. Any `1.x.x` release represents a post-MVP release.
  - **Patch `P`** resets to `0` at iteration start and bumps only on the active
    branch.
- **Todo / backlog cards carry a plain descriptive heading only** — no
  `Iteration N`, no `feat/iteration-N-…` branch, no semver in the body until the
  card starts.

## 3. Branching & git safety

- Prefer **trunk-based flow:** create a feature branch from the repo's trunk,
  open a PR, merge back. **One branch per unit of work.**
- **"Trunk" = whichever default branch the repo actually uses** — it may be
  `main` or `master`, and it differs between repos. Determine it from the repo
  (e.g. `git symbolic-ref refs/remotes/origin/HEAD`) rather than assuming one;
  "from trunk" throughout this file means that branch.
- **Never stack branches** — always branch from trunk, never from another
  feature branch.
- **Do not commit or push unless the user explicitly asks.** (A completed PR
  review batch is commit consent for *that batch only* — see §5.)
- **Never** force-push to `main`/`master`; avoid destructive git
  (`reset --hard`, `push --force`, history rewrites) unless the user explicitly
  requests it.
- **Never** update git config, and **never** skip hooks (`--no-verify`) unless
  explicitly told to.
- Do not revert or discard unrelated user changes; keep the worktree scoped to
  the task at hand.

## 4. CI after every push

> This procedure is packaged as the **`ci-watch`** skill (in
> `agent-shared/skills/`). Invoke that skill to run it; the steps below are its
> canonical description.

When a repo has CI and a commit is pushed (or the user asks to verify CI):

- **Monitor every pipeline that commit triggers through to completion.** Do not
  stop at the first status check and **never report a pending pipeline as the
  final result.**
- **Default CI is Woodpecker.** Most repos run **Woodpecker CI** — monitor the
  Woodpecker pipeline for that commit through to completion, using the
  **Woodpecker MCP** when available (`get_pipeline_status`, `list_pipelines`,
  `get_logs`). Woodpecker also mirrors its result to the GitHub commit status,
  so `gh api repos/<owner>/<repo>/commits/$SHA/status --jq '.state'` is a valid
  read of the same outcome when the MCP is unavailable.
- **Only repos not on Woodpecker** rely on GitHub-native CI — for those, poll
  the GitHub commit status for the pushed SHA
  (`gh api repos/<owner>/<repo>/commits/$SHA/status --jq '.state'` → expect
  `success`).
- **On failure**, reproduce the failing check locally using the repo's
  documented commands, make a narrow fix, commit (when the user has asked),
  push, and **re-monitor until green.**
- If neither the Woodpecker MCP nor `gh` is available, or the status stays
  `pending`, say so once and ask whether to wait/retry or use the Woodpecker UI.
  **Never invent a CI outcome.**

## 5. Pull requests: self-review, then triage

> This procedure is packaged as the **`pr-review-loop`** skill (in
> `agent-shared/skills/`). Invoke that skill to run it; the steps below are its
> canonical description.

**Self-review every PR you open.** Immediately after opening (or pushing to) a
PR, review the full diff against the repo's review rubric
(`.woodpecker/pr-review-prompt.md` where present) — correctness, security/OWASP,
tests, versioning, scope — and post the result as a GitHub PR review with `gh`
(inline comments on real RIGHT-side diff lines where possible). Treat remote
review agents as **supplementary and unreliable**, not the primary path.

**Then run the comment loop** for every unresolved thread (yours, humans', and
bots' — treated equally):

1. Fetch unresolved threads via GraphQL (`reviewThreads` where
   `isResolved == false`).
2. **Present one comment at a time** — file/line, author, full body, your
   analysis, and concrete fix option(s) including an explicit ignore/push-back.
3. **The user decides every comment.** Never change code for a review comment
   without an explicit choice.
4. Apply approved changes locally and sanity-check, but **accumulate the batch**
   before committing.
5. **Reply on the PR thread** with the resolution, and resolve the thread only
   when the user picked a fix or an explicit won't-do (leave "discuss further"
   open).
6. **One commit per batch** — never one-per-comment, never a force-push. The
   resolution audit trail stays on the PR, not in back-channel chat.

## 6. Automated test coverage

- Add or update automated tests for the behavior each change adds or alters.
  Pre-existing green tests are **not** sufficient when the changed behavior
  isn't directly asserted.
- Put coverage at the **lowest responsible layer**, and add integration/e2e
  coverage when behavior crosses a process, protocol, auth, persistence,
  deployment, or user-visible boundary.
- **Deliver tests in the same PR** as the behavior. If coverage is genuinely
  impractical, record the uncovered behavior, the reason, and the narrowest
  manual check in the PR/card — never omit silently.

## 7. MCP discipline & secrets

- On an MCP failure, follow that integration's **documented canonical fix**
  before improvising config changes — no partial env merges, no guess-and-check
  JSON churn.
- Batch related config edits and give **one** explicit reload boundary (MCP
  reload *or* full client restart), not a restart loop.
- **Never paste secrets** from `~/.claude.json`, `~/.cursor/mcp.json`, env
  files, or any credential store into chat, logs, tool arguments, or source
  control.

---

## 8. Commit message conventions

<!-- Baseline default — a repo may override with its own convention. -->

- Prefer [Conventional Commits](https://www.conventionalcommits.org/):
  `type(scope): summary` (`feat`, `fix`, `chore`, `docs`, `refactor`, `test`,
  `perf`).
- Imperative mood, subject under ~72 characters; explain the *why* in the body
  when it isn't self-evident.
- One commit per PR/iteration where the repo squash-merges.

## 9. General code style

<!-- Baseline default — a repo may override with its own convention. -->

- Match the surrounding code; consistency beats personal taste.
- Prefer clear names over comments; comment the *why*, not the *what*.
- Keep changes scoped to the task; handle errors explicitly.
- Run the project's configured formatter/linter before committing.
