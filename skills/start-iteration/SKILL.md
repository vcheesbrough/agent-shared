---
name: start-iteration
description: Start a bored iteration - move the card to In Progress, assign the next iteration number N, set the card heading, create the feature branch, and set the workspace version
---

# start-iteration

Use this when the user says to **start / pick up / implement** a bored card
(e.g. "start #142", "implement this card"). It takes a card from TODO to an
active iteration. Do **not** run it for a card that should stay in TODO — while
a card is TODO it is spec only; refining it is `update_card`, not this skill.

**One card, one branch, one N.** Do not split an iteration across cards or
branches, and do not stack branches.

## Steps

1. **Resolve the card.** Use bored MCP: `get_card_by_number` for `#N`, or
   `list_cards` on the repo's board. Confirm it is the card to start.

2. **Move it to In Progress.** `list_columns` for the board → `move_card` into
   the In Progress column.

3. **Assign the iteration number `N`.** Assign `N` **only now**, sequentially:
   `highest existing N + 1` across Done + In Progress cards (or `1` if none).
   Unless the repo says otherwise, `N` = the workspace semver **minor**.

4. **Reconcile the card with the source tree.** Compare the card body to the
   current repo; replan if scope or facts drifted.

5. **`update_card`** so the card records:
   - the first `#` heading as `# Iteration N — <description>` (one prefix; keep
     the descriptive title after the em dash);
   - **Branch:** `feat/iteration-N-short-slug` (from trunk);
   - **Version:** the workspace version, once a version file exists (see below).

6. **Create the branch** `feat/iteration-N-short-slug` from the repo's **trunk**
   (`main` or `master` — detect it, don't assume). Never branch from another
   feature branch.

7. **Set the workspace version** (when a version file exists):
   - **Pre-MVP** (before the MVP lands on trunk): `0.N.0`.
   - **Post-MVP** (after `1.0.0` is on trunk): `1.N.0`, with `N` continuing.
   - Patch resets to `0` at iteration start.

Now implement against the card's acceptance criteria, scoped to this card.

## Repo overrides

Some repos override this convention — e.g. an **operations repo** may name
branches after the card (`feat/<slug>`) with **no** iteration number or semver.
Check the repo's `AGENTS.md`: if it overrides baseline §2, follow the repo, not
this skill.

## Repo-specific bits

The board slug/URL, whether the MVP has shipped (pre- vs post-MVP semver), and
any version-file location come from the repo's own `AGENTS.md`.
