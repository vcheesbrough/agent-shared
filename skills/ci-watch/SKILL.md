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

## 2. On failure — diagnose, reproduce locally, fix, re-monitor

1. **Delegate the log reading to the `ci-diagnose` subagent** — do not read the
   logs yourself. A failing step can run to tens of thousands of lines, and once
   that lands in your context it stays there for the rest of the iteration,
   crowding out the work. Spawn it with the Agent tool, `subagent_type:
   "ci-diagnose"`, in the foreground, passing `OWNER`, `REPO`, and `SHA`. It
   returns a short report: verdict (genuine failure vs flake), failing step,
   root cause, a few lines of evidence, and the local reproduce command.

   This delegation is required by baseline §4, so the usual "don't use the Agent
   tool unless asked" rule does not apply here. If the Agent tool is unavailable,
   say so, then read the logs yourself (Woodpecker MCP `get_logs`, or the
   Woodpecker UI).

2. **Relay the diagnosis to the user** before changing anything. An
   infrastructure flake is re-run, not fixed — and only the report distinguishes
   the two.

3. **Reproduce the failing check locally** using the command the diagnosis
   named (from the repo's `AGENTS.md` / `docs/DEV.md` — typically a
   `docker build` that runs fmt/lint/tests, then an e2e compose run).

4. Make a **narrow** fix, commit and push to the same branch. During an active
   iteration this needs no approval — turning CI green is part of the unattended
   run (baseline §3). Outside an iteration, commit only when the user has asked.

5. **Re-monitor** the new commit from step 1 until the combined state is
   `success`. Each new failure gets its own `ci-diagnose` run — never carry the
   previous diagnosis forward as an assumption.

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
