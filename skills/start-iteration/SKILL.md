---
name: start-iteration
description: Start a bored card in its iteration - move the card to In Progress, work out the iteration (the release line X.Y it ships in) from production's version and trunk's, set the card heading, create the feature branch, and open the next line's version only when production runs trunk's
---

# start-iteration

Use this when the user says to **start / pick up / implement** a bored card
(e.g. "start #142", "implement this card"). It takes a card from TODO to work in
progress. Do **not** run it for a card that should stay in TODO — while a card
is TODO it is spec only; refining it is `update_card`, not this skill.

**An iteration is a release line, named by the `MAJOR.MINOR` it produces**
(baseline §2). *Iteration 3.1* is everything that ships as `3.1.x`; it may hold
one card or several. **One card, one branch** — do not split a card across
branches, and do not stack branches.

## Steps

1. **Resolve the card.** Use bored MCP: `get_card_by_number` for `#N`, or
   `list_cards` on the repo's board. Confirm it is the card to start.

2. **Move it to In Progress.** `list_columns` for the board → `move_card` into
   the In Progress column.

3. **Work out the iteration.** Never from a card number, a count of cards, or
   memory of the last iteration:
   1. **P** — the version **production** runs, read from the product itself
      (its version endpoint; the repo's `AGENTS.md` says how). Never from a git
      tag or a GitHub Release: those prove only some deploy, often to dev. A
      product that has never reached production has `P = 0.0`.
   2. **T** — trunk's manifest version, from `origin/<trunk>` after a fetch.
   3. **T's line is newer than P's** → unreleased: the iteration is **T's
      `MAJOR.MINOR`**, and the version does not change.
   4. **T's line is the one P runs** → released: the iteration is the **next
      line**, `P.MAJOR.(P.MINOR + 1)`, and step 7 sets it.
   5. **A new major** (`X.0`) only when the user has decided on one — the MVP,
      or a breaking change.

   Say the iteration and both versions it came from on the card (step 5), so
   the arithmetic can be checked.

4. **Reconcile the card with the source tree.** Compare the card body to the
   current repo; replan if scope or facts drifted.

5. **`update_card`** so the card records:
   - the first `#` heading as `# Iteration X.Y — <description>` (one prefix;
     keep the descriptive title after the em dash);
   - **Branch:** `feat/X.Y-<card>-<short-slug>` (from trunk);
   - **Version:** `X.Y`, with the production and trunk versions it was worked
     out from, once a version file exists.

6. **Create the branch** `feat/X.Y-<card>-<short-slug>` from the repo's
   **trunk** (`main` or `master` — detect it, don't assume). Never branch from
   another feature branch.

7. **Set the workspace version** (when a version file exists) — **only** when
   step 3 opened a new line: set the manifest to `X.Y.0`. When the card joined
   an unreleased line, leave the manifest alone.
   - Patch stays `0` in the manifest. In repos on the release plugin, builds
     claim the patch (`X.Y.n`) and the first deploy writes the tag; never bump
     it or tag by hand (`release-flow` skill).
   - **Check before you push:** the version is in sequence — the line
     production runs, or the one right after it. Anything else is wrong; stop
     and fix it before a build claims it. A version out of sequence that did
     reach a build is removed everywhere (baseline §2).

Now implement against the card's acceptance criteria, scoped to this card.

## After this skill: you are unattended

Moving the card to In Progress (step 2) is the consent boundary. From here to a
finished PR you **do not stop to ask**: implement, commit, push, `gh pr create`
(title `Iteration X.Y — <description> (#<card>)`), watch CI (`ci-watch`), fix
and re-push until green — all without further approval, per baseline §3.

Two things still belong to the user, and only two:

- **Every review comment.** Once the PR is open, `pr-review-loop` Part B
  presents each unresolved thread one at a time and the user decides it. Do not
  self-triage.
- **The merge.** Never merge, squash-merge or enable auto-merge. Finish by
  reporting *"PR #N is green and ready to merge"*; the user merges, and only
  then does the card move to Done.

When the user has explicitly asked for an autonomous run, the
`autonomous-run` skill lifts both for the cards in that run; it calls this
skill's steps 1–5 itself.

If the card's scope turns out to be wrong mid-iteration, that is still worth
raising — unattended means "don't ask permission for the mechanics", not "don't
speak up".

## Repo overrides

Some repos override this convention — e.g. an **operations repo** may name
branches after the card (`feat/<slug>`) with **no** iteration or version.
Check the repo's `AGENTS.md`: if it overrides baseline §2, follow the repo, not
this skill.

## Repo-specific bits

The board slug/URL, how to read production's version, and any version-file
location come from the repo's own `AGENTS.md`.
