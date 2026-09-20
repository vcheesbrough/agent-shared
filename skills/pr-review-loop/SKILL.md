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

**Opening the PR is unattended; merging it never is.** During an iteration you
`gh pr create` without asking (baseline §3), but the two gates in this skill
stay: the user decides every review comment, and the user performs the merge.

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

2. **Present one comment at a time.** For each unresolved thread, first write
   out in the message: file + line, author, the **full comment body**, and your
   **analysis** (what they meant, whether it matters). Then ask for the
   decision.

   **Always ask with the `AskUserQuestion` tool — never as plain prose.** The
   decision UI is not a nicety that depends on how many options there happen to
   be; it is the uniform way this loop collects decisions, so every thread gets
   the same interface and the choice is recorded the same way. Even a
   straight-up "fix it or not" is asked as a two-option question, not as a
   typed-out yes/no.

   One call per thread — **never** bundle several threads into one call's
   questions array, even when they look related. Shape it as:

   - `header`: a ≤12-char tag, e.g. the file stem or `nullcheck`.
   - `question`: the decision to make on this thread, in one sentence.
   - `options`: 2–4 concrete resolutions, each `label` a short imperative
     ("Add the bounds check") and each `description` saying what changes and
     what it costs. Put your recommendation first, suffixed
     `(Recommended)`.
   - **One option is always an explicit ignore / push back** — "Won't fix,
     reply on the thread" — with the description saying what goes in the reply.
   - `multiSelect: false` unless the fixes genuinely compose.

   The tool adds its own "Other" escape, so do not spend an option on one. If
   the user picks Other or answers with free text, treat that as the decision
   and carry on — do not re-ask the same thread through the tool.

   **The user decides.** A thread whose answer is "let's discuss" gets no code
   change and stays unresolved.

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

7. **Hand the PR back.** When no unresolved threads remain and CI is green,
   report *"PR #$PR is green and ready to merge"* and stop. **Do not merge** —
   see the hard rules.

---

## Hard rules

- **User decides every comment** — never change code for a review comment
  without an explicit choice.
- **One comment per prompt** — don't batch multiple comments into one decision.
- **Every decision goes through `AskUserQuestion`** — one call per thread, with
  an explicit ignore/push-back option. No prose A/B/C prompts, no plain yes/no,
  regardless of how obvious or how binary the choice looks.
- **One commit per batch** — never one-per-comment, never a force-push.
- **Don't auto-resolve** threads the user marked "discuss further" or "skip".
- **All resolution explanations go on the PR**, not back-channel chat.
- Self-review is **required** when you open the PR; remote agent output is
  optional/supplementary.
- **The author never reviews their own diff** — Part A goes to the
  `pr-self-review` subagent, with coordinates only and no design rationale.
- **Never merge the PR.** No `gh pr merge`, no squash/rebase merge, no
  `--auto`, and never close a PR instead of merging it. The merge is the user's
  approval gate and the last human decision in the iteration.

## Repo-specific bits

`OWNER`/`REPO` and the sanity-check commands come from the repo's own
`AGENTS.md`, which is also where any review criteria beyond the baseline five
live — the subagent reads it directly. Merge/branch-cleanup conventions (e.g. squash + delete
branch) also live there — follow them at ship time.
