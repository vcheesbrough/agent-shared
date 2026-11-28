---
name: autonomous-run
description: Work one or more bored cards end to end with no user in the loop - start each iteration, implement, open the PR, take the recommended resolution on every review thread, and merge once the PR clears the merge bar. Several cards run concurrently, each in its own git worktree. Use ONLY when the user explicitly asks for autonomous or unattended work ("work these cards autonomously", "autopilot the board", "do #12 and #14 and merge them"); never infer it.
---

# autonomous-run

The normal iteration (baseline §2–§5) is unattended up to an open, green PR,
and then stops twice for the user: once per review thread, and once for the
merge. This skill removes those two stops **for the cards named in this run
only**:

- **Review threads:** you take your own recommended option instead of asking.
- **The merge:** you merge once the PR clears the merge bar below.

Everything else in the baseline still applies unchanged: one card = one branch
= one N, never stack, no force-push, no `--no-verify`, no git config edits, no
hand-written tags, tests in the same PR (§6), CI watched to completion (§4),
the self-review from a clean context (§5).

## Models

In this skill the main session only orchestrates. It reads the board, works
out versions, manages worktrees, watches CI, relays messages and checks the
merge bar. It never writes card code, so it can run on **Sonnet**. Every
agent it spawns gets its model explicitly, never by inheritance:

| Agent | Model |
| --- | --- |
| `card-worker` | the card's **tier** (§1a): Sonnet, Opus or Fable. A `**Model:**` line on the card overrides the tier. |
| `pr-self-review` | Opus, or **Fable** when the worker runs on Fable (complex tier or pinned). A reviewer is never weaker than the worker whose code it reviews. |
| `ci-diagnose` | its own frontmatter (Sonnet) |

Set the model with the Agent tool's `model` parameter on every spawn. Workers
are never forks: a fork always inherits the session's model.

## Consent and scope

- **Explicit invocation only.** Run this skill only when the user's own words
  ask for autonomous / unattended work. A request to "start #12" is
  `start-iteration`, not this.
- **The run is the scope.** Consent covers the cards the user named, or, if
  they said "the board" / "the Todo column", the cards in Todo at the moment
  the run starts. Cards created during the run (including follow-ups deferred
  from review) are **not** picked up. Consent ends when the run ends; the next
  iteration in a later conversation is attended again unless re-invoked.
- **Read the repo's `AGENTS.md` first.** A repo that forbids autonomous merges,
  or names a different merge method, wins over this skill.

## 1. Plan the run

1. Resolve every card with bored MCP (`get_card_by_number` / `list_cards`).
2. Read their **before/after links**. A card linked after another card in this
   run depends on it: it starts only once its predecessor has **merged**, from
   updated trunk. Never branch it from the predecessor's branch.
3. Group the cards into **waves**: wave 1 is every card with no unmerged
   predecessor in the run. Within a wave, also serialise two cards whose
   bodies say they change the same files or the same schema/migration — they
   would only conflict at merge time.
4. **No concurrency cap.** Every card in a wave starts at once — 20 independent
   cards means 20 worktrees and 20 workers. Only dependencies (step 2) and
   overlapping changes (step 3) put a card in a later wave; never the count.
5. **Tier every card** (§1a).
6. Tell the user the plan in a few lines (waves, order, each card's tier),
   then start. Do not wait for approval: the invocation was the approval.

**A single card** needs no worktree, but it still gets a worker. Run
`start-iteration` in the main checkout, then spawn one `card-worker` at the
card's tier with the main checkout as its worktree, and apply §3–§5. The
session never writes the card's code itself. If it did, the card would be
built by whatever model the session runs on.

### 1a. Tier each card

The tier picks the worker's model. Judge it from the card's body, its
acceptance criteria, and the files and subsystems it names. Look at the repo
where the card is vague.

| Tier | Worker model | The card… |
| --- | --- | --- |
| **light** | Sonnet | changes no production logic: docs, comments, copy, config values, a renamed symbol, a dependency bump that needs no code change. It is bounded and names its files. |
| **standard** | Opus | is a real code change. **This is the default.** |
| **complex** | Fable | needs design work: it crosses several crates, services or processes; it adds or retires an API version (`api-versioning`); it carries a schema or data migration that must stay compatible with the previous release (`migrations`); it redesigns an auth or security boundary; it involves concurrency or consistency reasoning; or its acceptance criteria leave a real design decision open. This tier should be rare. |

- **When in doubt, go up a tier.** A light card on Opus wastes a little. A
  complex card on Sonnet wastes a whole run and risks a bad merge.
- **A `Model:` line on the card pins the worker's model.** If the card body
  has a line such as `**Model:** fable`, spawn its worker at that model and
  skip tiering it. The user wrote the line, so it beats your judgment in
  both directions. Accept any value the Agent tool's `model` parameter takes
  (`sonnet`, `opus`, `fable`, `haiku`). If the value is anything else, tier
  the card as usual and say so in the plan.
- Record the tier when the card starts (§2 step 1), as one line in the body:
  `**Tier:** standard — <one-clause reason>`, or for a pinned card
  `**Tier:** pinned — Model: fable, set on the card`. This keeps the call
  auditable and lets the user correct it on the board.

## 2. Start each card (orchestrator, serially)

The iteration — the release line `X.Y` a card ships in — must be worked out
by one actor in one order, so that only one card opens a new line and the rest
join it. So the orchestrator — you, the main session — starts every card
itself, one at a time, in the order the plan gives:

1. Run `start-iteration` steps 1–5 for the card (move to In Progress, work out
   the iteration from production's and trunk's versions, reconcile,
   `update_card`, adding the `**Tier:**` line from §1a). Work it out only when
   the card actually starts, so a wave-2
   card reads the versions as they are when wave 2 begins. Cards in one run
   share an iteration unless a release reaches production during the run; only
   the first card to open a new line sets the manifest version.
2. Instead of `git checkout -b`, create a **worktree** on the new branch from
   up-to-date trunk:

   ```bash
   git fetch origin
   WT="$(git rev-parse --show-toplevel)/../$(basename "$(git rev-parse --show-toplevel)").wt/card-$C"
   git worktree add -b "feat/$XY-$C-<slug>" "$WT" "origin/$TRUNK"
   ```

3. Spawn one **worker** per card: Agent tool, `subagent_type: "card-worker"`,
   `model` set from the card's tier (§1a), in the background, with the brief
   in [§2a](#2a-worker-brief). Keep its agent ID: you continue the same
   worker with `SendMessage` for every later step on that card, until an
   escalation (§3a) replaces it.

### 2a. Worker brief

The `card-worker` agent already carries the standing rules: worktree only, no
self-review, no subagents, no merge, compose project names, what to reply
with. Give it coordinates, not your own plan for the card. It reads the card
itself:

> Implement bored card #C (board `<slug>`) in **Iteration X.Y**, in the git
> worktree `<WT>` on branch `feat/X.Y-C-<slug>`.
> `<Set the workspace version to X.Y.0 | Leave the workspace version as it is>`
> (start-iteration step 7).
> `<Run e2e locally | Do not run e2e; the orchestrator will tell you when>`.

If several workers would run local e2e / `docker compose` checks against
hard-coded host ports, they collide. Brief only one at a time to run e2e and
serialise the rest.

## 3. Drive each PR (per card)

For each card, as its worker reports a PR:

1. **CI** — run `ci-watch` on the head SHA. On failure, *you* spawn
   `ci-diagnose` (workers never spawn subagents) and `SendMessage` the diagnosis
   to the worker to fix and push. Give up on the card after **3** consecutive
   failed fix attempts (§6).
2. **Self-review, full round** — *you* spawn `pr-self-review` with coordinates
   only, exactly as `pr-review-loop` Part A says, at the model in **Models**
   above (`model: "fable"` when the worker runs on Fable). Never pass the worker's
   report, rationale or tier along.
3. **Triage** — `SendMessage` the worker: *"Triage every unresolved thread on
   PR #P per autonomous-run §4, one commit, push, reply with the new head
   SHA."* The worker has the implementation context, so it makes the
   recommendation, exactly as the attended loop's author would.
4. **CI again**, then a **delta round** of `pr-self-review` with `SINCE=` the
   previous reviewed head.
5. **Round limit.** Autonomous runs get the full round plus **one** delta
   round. If the delta round raises another correctness or security finding,
   one more triage batch is allowed, but no third review: if that batch's fix
   is anything other than trivially local, stop the card (§6) rather than
   merging a fix nobody re-reviewed.
6. When the PR clears the merge bar (§5), merge it.

### 3a. Escalating a card's tier

A tier is a guess, so a card may move up **one** tier, **once**, when its
worker shows the guess was low:

- `ci-diagnose` calls **two consecutive** fix attempts genuine failures (not
  infrastructure);
- the worker reports it cannot meet an acceptance criterion; or
- *light cards only:* the full self-review round raises a correctness or
  security finding. A card that has one was not light.

To escalate:

1. End the current worker (`TaskStop`).
2. Update the card's tier line:
   `**Tier:** standard — escalated from light: <why>`.
3. Spawn a new `card-worker` at the higher tier's model, in the **same
   worktree and branch**. Use the same brief, plus:
   *"Escalation: PR #P is already open on this branch from a <tier> worker.
   Continue from where it stands."*
4. Carry on with §3 from the step you were at. The new worker gets a fresh
   budget of 3 CI fix attempts. The review round count does **not** reset.

A complex card cannot escalate, and neither can a card whose model is
**pinned** by a `**Model:**` line: the user chose that model, so don't
overrule it. If either hits these signals, the normal stop rules (§6) apply.
The stop comment on the PR names the pinned model, so the user can raise it
and re-run.

Escalate only on these signals. The merge bar is the same whichever model
wrote the code. Escalation is about cost, not a second chance to merge.

## 4. Taking the recommended option (worker)

This is `pr-review-loop` Part B with the user replaced by the recommendation.
For every unresolved thread — self-review, human, or bot alike:

1. Build the same option set Part B would put in `AskUserQuestion`: narrowest
   fix first, **Defer to a follow-up card** when the right fix outgrows the
   PR, and an explicit **Won't fix** with its reason. Pick the one you would
   have marked *(Recommended)*. Do **not** call `AskUserQuestion`.
2. Hold the recommendation to the same bar as when a human is watching:
   - A **correctness or security** finding you agree with is fixed, not
     deferred. Deferral is for scope, never for difficulty.
   - **Scope only shrinks.** The fix is the narrowest change that resolves the
     thread; anything that touches code the PR didn't change is deferred.
   - **Won't fix** needs a concrete reason the finding is wrong or not worth
     it, not "out of time".
   - A **human** reviewer's thread asking for a change of direction (not a
     code fix) is not yours to overrule: leave it unresolved and report it —
     it blocks the merge.
3. Apply the edits; for a deferral, create the Todo card (linked after this
   iteration's card) with bored MCP.
4. **Reply on the thread**, prefixed so the audit trail shows no human chose
   it, then resolve it:

   > **Autonomous run — took the recommended option:** <option>. <one or two
   > sentences of why, and what changed / which card it was deferred to>.

5. One commit for the whole batch, push, report the head SHA.

## 5. The merge bar

Merge only when **all** of these hold on the PR's current head:

- [ ] CI is green for the head SHA — every pipeline, not just the first.
- [ ] Zero unresolved review threads, and none left open by a human (§4.2).
- [ ] The last self-review round raised no correctness or security finding
      that was resolved as *won't fix* or *defer*.
- [ ] The card's acceptance criteria are met and the changed behaviour is
      tested (§6), or the gap is recorded on the PR and the card.
- [ ] The branch is mergeable against current trunk (see below).
- [ ] The repo's `AGENTS.md` adds nothing that is still unmet.

**Bringing a branch up to date.** If trunk has moved (typically because an
earlier card in this run merged), merge trunk *into* the branch — never
rebase, never force-push — resolve conflicts in the worker, push, and re-run
CI. A conflict resolution that changes behaviour (not just versions or
imports) needs a delta self-review before merging.

**Version files.** Merge in ascending `N` where possible, so trunk's version
only rises. If a lower-`N` card is stuck, merge the higher one anyway; when the
stuck one later merges trunk in, resolve the version conflict to the higher
version. Trunk's version never goes backwards.

**Merging.** Use the repo's merge convention from its `AGENTS.md`; if it is
silent, `gh pr merge <P> --squash --delete-branch`. Never `--admin`, never
bypass branch protection, never `--auto` on a PR that has not met the bar.

**After the merge:**

1. Run `ci-watch` on the trunk merge commit — this may include a deploy. If
   trunk goes red, **stop merging** anything else in the run, and report.
2. Move the card to **Done** (baseline §1).
3. Remove the worktree: `git worktree remove "$WT"` and delete the local
   branch. End the worker.
4. Start any card whose predecessors are now all merged (§2).

## 6. Stopping a card

Autonomy is for mechanics, not for overriding a reason to stop. Stop the card
— leave its PR open, its card In Progress, its worktree in place — and carry
on with the rest of the run when:

- CI still fails after 3 fix attempts, or `ci-diagnose` calls it an
  infrastructure fault you cannot re-run past;
- the card is ambiguous enough that a wrong guess would ship the wrong
  feature (a guess on a detail is fine — record it on the card and the PR);
- a human reviewer's thread blocks it (§4.2), or the round limit (§3.5) is hit;
- the change needs an action outside the PR: a production data migration run
  by hand, secrets, infra or DNS changes, anything destructive.

Comment on the PR saying why it stopped, so the state is visible without this
conversation.

## 7. Report

When every card has merged or stopped, finish with one line per card:
card, iteration, **tier** (and any escalation), PR, outcome (*merged* + trunk
CI state, or *stopped* + why), and any follow-up cards created from deferred
threads. The tier column is the only feedback the tiering gets. Keep it, so
the user can tell whether light cards are holding up. Every review decision
you took on the user's behalf is already on its PR thread; point at them rather
than repeating them.
