#!/usr/bin/env bash
#
# install.sh — wire this machine up to the agent-shared config.
#
# Idempotent. Creates the symlinks that make agent-shared the single source of
# truth for AI-agent config on this machine:
#
#   ~/.codex/AGENTS.md        -> global/AGENTS.md   (Codex baseline)
#   ~/.claude/CLAUDE.md       -> global/AGENTS.md   (Claude Code baseline)
#   ~/.claude/skills/<name>   -> skills/<name>      (personal skills, all repos)
#   ~/.agents/skills/<name>   -> skills/<name>      (Codex skills, all repos)
#
# Usage:
#   ./install.sh            create/refresh all links
#   ./install.sh --dry-run  show what would change, do nothing
#
# Safe to re-run: correct links are left alone, a real file/foreign link in the
# way is backed up to <path>.bak-<timestamp> before the link is created, and
# skill links pointing into this repo whose target no longer exists are pruned.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && DRY_RUN=1

changed=0

say()  { printf '%s\n' "$*"; }
run()  { if [[ $DRY_RUN -eq 1 ]]; then say "  [dry-run] $*"; else eval "$*"; fi; }

# link <target> <linkpath>
link() {
  local target="$1" linkpath="$2"
  run "mkdir -p '$(dirname "$linkpath")'"

  if [[ -L "$linkpath" ]]; then
    local cur; cur="$(readlink "$linkpath")"
    if [[ "$cur" == "$target" ]]; then
      say "  ok      $linkpath"
      return
    fi
    say "  relink  $linkpath (was -> $cur)"
    run "rm '$linkpath'"
  elif [[ -e "$linkpath" ]]; then
    local bak="$linkpath.bak-$(date +%Y%m%d%H%M%S)"
    say "  BACKUP  $linkpath -> $bak"
    run "mv '$linkpath' '$bak'"
  else
    say "  link    $linkpath -> $target"
  fi

  run "ln -s '$target' '$linkpath'"
  changed=$((changed + 1))
}

say "agent-shared: installing from $REPO"
[[ $DRY_RUN -eq 1 ]] && say "(dry run — no changes will be made)"

# --- baselines ---
link "$REPO/global/AGENTS.md" "$HOME/.codex/AGENTS.md"
link "$REPO/global/AGENTS.md" "$HOME/.claude/CLAUDE.md"

# --- skills (one pair per skills/<name>) ---
run "mkdir -p '$HOME/.claude/skills' '$HOME/.agents/skills'"
for dir in "$REPO"/skills/*/; do
  [[ -d "$dir" ]] || continue
  name="$(basename "$dir")"
  link "$REPO/skills/$name" "$HOME/.claude/skills/$name"
  link "$REPO/skills/$name" "$HOME/.agents/skills/$name"
done

# --- prune dangling skill links that point into this repo ---
for base in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  [[ -d "$base" ]] || continue
  for l in "$base"/*; do
    [[ -L "$l" ]] || continue
    tgt="$(readlink "$l")"
    case "$tgt" in
      "$REPO/skills/"*)
        if [[ ! -e "$tgt" ]]; then
          say "  prune   $l (target gone: $tgt)"
          run "rm '$l'"
          changed=$((changed + 1))
        fi ;;
    esac
  done
done

say ""
if [[ $DRY_RUN -eq 1 ]]; then
  say "Dry run complete. Re-run without --dry-run to apply."
else
  say "Done. $changed link(s) changed."
fi
