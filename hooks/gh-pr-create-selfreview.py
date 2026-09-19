#!/usr/bin/env python3
"""PostToolUse(Bash) hook: re-assert the self-review rule the moment a PR opens.

Baseline §5 requires every PR you open to be self-reviewed from a clean
context. That rule is easiest to skip at exactly the point it applies — the
agent has just finished the work and is in a hurry to report success. This hook
watches Bash calls for a successful `gh pr create` and feeds the requirement
back into the transcript with the PR number already filled in.

Fires only when the command actually created a PR: success is detected from the
PR URL that `gh pr create` prints, so `--help`, `--dry-run`, and failed runs are
all silently ignored.

Wire it up in ~/.claude/settings.json:

    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /home/vincent/dev/agent-shared/hooks/gh-pr-create-selfreview.py",
            "timeout": 5
          }
        ]
      }
    ]
"""

import json
import re
import sys

PR_URL = re.compile(r"https://github\.com/[^/\s]+/[^/\s]+/pull/(\d+)")


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return

    command = data.get("tool_input", {}).get("command", "")
    if "gh pr create" not in command:
        return

    response = data.get("tool_response", {})
    if not isinstance(response, str):
        response = " ".join(
            str(response.get(key, "")) for key in ("stdout", "stderr", "output")
        )

    match = PR_URL.search(response)
    if not match:
        return

    context = (
        f"RULE (baseline §5): PR #{match.group(1)} was just opened. Invoke the "
        "pr-review-loop skill now, before reporting the PR to the user. Part A "
        "delegates the review to the pr-self-review subagent — do NOT review "
        "the diff yourself, and pass coordinates only (owner, repo, PR number, "
        "trunk), never your rationale for the changes."
    )

    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": context,
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    main()
