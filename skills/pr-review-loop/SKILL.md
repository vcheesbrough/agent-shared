---
name: pr-review-loop
description: Self-review a pull request you opened, post it to GitHub, then resolve every unresolved review thread one at a time with the user deciding each and one commit per batch
---

# PR review loop

Use this when you **open or push to a PR** (self-review) and whenever a PR on
the current branch has **unresolved review threads** — from your own review,
another agent, or a human. Part A authors a review; Part B resolves review
threads. Run A then B when you opened the PR; run B alone when triaging existing
comments.

Set these once:

```bash
OWNER=<github-owner>        # e.g. vcheesbrough
REPO=<repo>                 # e.g. bored
PR=<pr-number>              # gh pr view --json number -q .number
```

Treat bot and human comments **equally**. The user decides every comment. Never
force-push. The resolution audit trail lives on the PR, not in chat.

---

## Part A — self-review the PR you opened

Do this immediately after `gh pr create` or a push to the PR branch. Do **not**
wait for remote review agents (Woodpecker `pr-review`, Cursor Automation,
Bugbot); treat them as supplementary and unreliable.

**Delegate the review to the `pr-self-review` subagent — do not review the diff
yourself.** You wrote the code; you already believe it is correct, and that
belief is what a self-review has to get past. The subagent starts with a clean
context: it sees the repo and the diff, but not the conversation that produced
them. This delegation is required by baseline §5, so the usual "don't use the
Agent tool unless asked" rule does not apply here.

1. **Spawn the subagent** with the Agent tool, `subagent_type:
   "pr-self-review"`, and run it in the foreground — Part B depends on its
   result and there is nothing useful to do meanwhile.

2. **Pass coordinates only:**

   > Review PR #$PR on $OWNER/$REPO. Trunk is `<trunk>`.

   **Nothing else.** No summary of what the branch does, no rationale for the
   design, no "I already checked X". Every such sentence hands the reviewer
   your bias back and spends the clean context you just paid for.

3. **Let it post its own comments.** The subagent files one inline comment per
   finding plus a summary comment, directly. It files **no review verdict** —
   unresolved threads are the signal that work remains. Do not offer to post
   findings on its behalf and do not filter, soften, or pre-argue them — that
   would put the author back in the loop.

4. **Relay what it found to the user** (finding count, severity, PR URL), then
   continue to Part B, where its comments are triaged exactly like any other
   reviewer's.

If the subagent is unavailable (no Agent tool in this environment), say so
explicitly, then review the diff yourself — correctness, security / OWASP,
tests, versioning, scope, plus whatever the repo's `AGENTS.md` adds — post the
findings as inline comments the same way, and note in the summary comment that
the review was authored without a clean context.

## Part B — triage and resolve threads

1. **Fetch unresolved threads** (both authors, `isResolved == false`):

   ```bash
   gh api graphql -f query='
     query($owner:String!,$repo:String!,$num:Int!) {
       repository(owner:$owner, name:$repo) {
         pullRequest(number:$num) {
           reviewThreads(first:100) {
             nodes { id isResolved
               comments(first:50) { nodes { id author{login} path line body url } }
             }
           }
         }
       }
     }' -F owner=$OWNER -F repo=$REPO -F num=$PR
   ```

2. **Present one comment at a time.** For each unresolved thread show: file +
   line, author, full comment body, your **analysis** (what they meant, whether
   it matters), and concrete **fix option(s)** — always including an explicit
   "ignore / push back" choice. Prompt A/B/C or yes/no. **The user decides.**

3. **Apply the chosen resolution locally.** Make the edits, run a quick sanity
   check (e.g. `cargo check`, `trunk build`), but **do not commit yet** —
   accumulate edits across the batch.

4. **Reply on the thread, then resolve it** when the user picked a fix or an
   explicit won't-do (leave "discuss further" open):

   ```bash
   gh api repos/$OWNER/$REPO/pulls/$PR/comments/$COMMENT_ID/replies \
     -f body="<resolution summary>"
   gh api graphql -f query='
     mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ id } } }' \
     -F id=$THREAD_ID
   ```

5. **End-of-batch commit + push** once every comment has a decision: **one**
   commit naming the PR and summarising the comments addressed, then `git push`
   to the same branch. Verify CI afterward (Woodpecker pipeline / commit status)
   before declaring the batch done.

6. **Re-enter Part B** when the user asks for the next round, or when polling
   reveals new unresolved threads (remote agents re-run on each push).

---

## Hard rules

- **User decides every comment** — never change code for a review comment
  without an explicit choice.
- **One comment per prompt** — don't batch multiple comments into one decision.
- **One commit per batch** — never one-per-comment, never a force-push.
- **Don't auto-resolve** threads the user marked "discuss further" or "skip".
- **All resolution explanations go on the PR**, not back-channel chat.
- Self-review is **required** when you open the PR; remote agent output is
  optional/supplementary.
- **The author never reviews their own diff** — Part A goes to the
  `pr-self-review` subagent, with coordinates only and no design rationale.

## Repo-specific bits

`OWNER`/`REPO` and the sanity-check commands come from the repo's own
`AGENTS.md`, which is also where any review criteria beyond the baseline five
live — the subagent reads it directly. Merge/branch-cleanup conventions (e.g. squash + delete
branch) also live there — follow them at ship time.
