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

1. **Load the rubric.** Use the repo's `.woodpecker/pr-review-prompt.md` if it
   exists; otherwise review for correctness, security / OWASP, tests, versioning,
   and scope. Read the touched files for context.
2. **Review the full diff** file-by-file: `gh pr diff $PR` (or
   `git diff <trunk>...HEAD`).
3. **Post one GitHub review** with `gh`:
   - Verdict: `--approve` only when truly clean, `--request-changes` for
     blockers, `--comment` for minor/informational.
     ```bash
     gh pr review $PR --request-changes --body "<summary: verdict + checks run>"
     ```
   - Inline comments on specific lines (blockers and majors at minimum) must
     reference real lines on the **RIGHT** side of the diff; include a
     ` ```suggestion ` block where a concrete replacement is possible. Use
     `gh api .../pulls/$PR/comments` or GraphQL
     `addPullRequestReviewComment` when `gh pr review` can't place them.
4. **Surface the verdict to the user**, then continue to Part B — treat your own
   inline comments like any other reviewer's.

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

## Repo-specific bits

`OWNER`/`REPO`, the rubric path, and the sanity-check commands come from the
repo's own `AGENTS.md`. Merge/branch-cleanup conventions (e.g. squash + delete
branch) also live there — follow them at ship time.
