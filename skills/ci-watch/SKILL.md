---
name: ci-watch
description: Monitor the CI pipeline for a pushed commit through to completion, reproduce any failure locally, and re-monitor until green
---

# ci-watch

Use this after **every** push (or when the user asks to verify CI). Do not stop
at the first status check and **never report a pending pipeline as the final
result**. Never invent a CI outcome.

Set these from the repo's `AGENTS.md`:

```bash
OWNER=<github-owner>        # e.g. vcheesbrough
REPO=<repo>                 # e.g. bored
SHA=$(git rev-parse HEAD)   # the pushed commit
```

## 1. Monitor to completion

**Default CI is Woodpecker.** Monitor the Woodpecker pipeline for `SHA` through
to completion:

- Prefer the **Woodpecker MCP** when available: `list_pipelines` to find the run
  for the branch/commit, `get_pipeline_status` to watch it, `get_logs` to read a
  failing step.
- Woodpecker also mirrors its result to the GitHub commit status, so this reads
  the same outcome when the MCP is unavailable, and is the path for
  **non-Woodpecker** repos:

  ```bash
  gh api repos/$OWNER/$REPO/commits/$SHA/status --jq '.state'            # expect: success
  gh api repos/$OWNER/$REPO/commits/$SHA/status --jq '.statuses[] | "\(.context): \(.state)"'
  ```

Keep polling while the state is `pending`. Report which checks ran and the
combined result (**success / failure / still pending**).

## 2. On failure — reproduce locally, fix, re-monitor

1. Read the failing step's logs (Woodpecker MCP `get_logs`, or the Woodpecker
   UI).
2. **Reproduce the failing check locally** using the repo's documented commands
   (from its `AGENTS.md` / `docs/DEV.md` — typically a `docker build` that runs
   fmt/lint/tests, then an e2e compose run).
3. Make a **narrow** fix. Commit only when the user has asked, push to the same
   branch.
4. **Re-monitor** the new commit from step 1 until the combined state is
   `success`.

All push steps (including any `e2e` stage) must be green before an iteration is
declared done.

## 3. Degrade gracefully

If neither the Woodpecker MCP nor `gh` is available, or the status stays
`pending`, say so **once** and ask whether to wait/retry or use the Woodpecker
UI. Do not report a guess as the result.

## Repo-specific bits

`OWNER`/`REPO`, the local reproduce commands, and any **post-pipeline** checks
that are not part of CI (e.g. a deployment smoke check hitting a live endpoint)
come from the repo's own `AGENTS.md`.
