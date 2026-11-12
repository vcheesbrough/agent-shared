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
4. Run at most **3 cards concurrently** unless the user set a different cap.
5. Tell the user the plan in a few lines (waves, order), then start — do not
   wait for approval; the invocation was the approval.

**A single card** needs no worktree and no worker: run `start-iteration` in
the main checkout and work it yourself, applying §3–§5 below.

## 2. Start each card (orchestrator, serially)

Iteration numbers must be assigned by one actor in one order, or two cards
take the same N. So the orchestrator — you, the main session — starts every
card itself, one at a time, in the order the plan gives:

1. Run `start-iteration` steps 1–5 for the card (move to In Progress, assign
   `N`, reconcile, `update_card`). Assign `N` only when the card actually
   starts, so a wave-2 card gets its number when wave 2 begins.
2. Instead of `git checkout -b`, create a **worktree** on the new branch from
   up-to-date trunk:

   ```bash
   git fetch origin
   WT="$(git rev-parse --show-toplevel)/../$(basename "$(git rev-parse --show-toplevel)").wt/iteration-$N"
   git worktree add -b "feat/iteration-$N-<slug>" "$WT" "origin/$TRUNK"
   ```

3. Spawn one **worker** per card (Agent tool, `general-purpose`, background)
   with the brief in [§2a](#2a-worker-brief). Keep its agent ID: you continue
   the same worker with `SendMessage` for every later step on that card.

### 2a. Worker brief

Give the worker coordinates and rules, not your own plan for the card — it
reads the card itself:

> You are implementing bored card #C (board `<slug>`) as **Iteration N** in the
> git worktree `<WT>` on branch `feat/iteration-N-<slug>`. Work only inside
> that worktree. Read `<WT>/AGENTS.md` and `~/.claude/CLAUDE.md` first, then
> `~/.claude/skills/autonomous-run/SKILL.md` §3–§4 — that is your procedure.
> Set the workspace version to `<0.N.0 | 1.N.0>` (start-iteration step 7).
> Implement the card's acceptance criteria with tests, run the repo's local
> checks, commit, push, and open the PR with `gh pr create`. **Do not** review
> your own PR, spawn subagents, merge, or move the card — the orchestrator
> does those. If the PR-create hook tells you to run `pr-review-loop`, ignore
> it: the orchestrator runs Part A. Reply with the PR number, the head SHA,
> and anything on the card you had to decide or could not do.

If several workers run local e2e / `docker compose` checks at once they will
collide on ports and project names: tell each worker to set
`COMPOSE_PROJECT_NAME=<repo>-it$N` and, where the repo's compose file
hard-codes host ports, to run its e2e step only when the brief says so — the
orchestrator then serialises those runs.

## 3. Drive each PR (per card)

For each card, as its worker reports a PR:

1. **CI** — run `ci-watch` on the head SHA. On failure, *you* spawn
   `ci-diagnose` (workers never spawn subagents) and `SendMessage` the diagnosis
   to the worker to fix and push. Give up on the card after **3** consecutive
   failed fix attempts (§6).
2. **Self-review, full round** — *you* spawn `pr-self-review` with coordinates
   only, exactly as `pr-review-loop` Part A says. Never pass the worker's
   report or rationale along.
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
card, iteration, PR, outcome (*merged* + trunk CI state, or *stopped* + why),
and any follow-up cards created from deferred threads. Every review decision
you took on the user's behalf is already on its PR thread; point at them rather
than repeating them.
