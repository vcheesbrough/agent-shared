---
name: release-flow
description: Build, release and promotion contract for repos that ship container images through Woodpecker (or GitHub Actions) - one build per push, a gap-free patch counter, promote never rebuild, the first deploy writes the git tag. Load before wiring or changing a repo's build or deploy pipeline, adding an image or a deploy target, deploying or answering which version runs where, bumping MAJOR.MINOR, migrating a repo off its own release scripts, or taking a product to 1.0.0.
---

# release-flow

**Premise.** A commit runs under exactly one version, chosen by its build and
fixed by its first deploy. Every environment runs the same image, built and
tested once; nothing is rebuilt to be promoted. The
[`woodpecker-plugin-release-versions`](https://github.com/vcheesbrough/woodpecker-plugin-release-versions)
plugin (0.2.0+) enforces this and refuses anything else at run time. This
skill is the contract *before* run time, so an agent never wires a pipeline
the plugin will refuse, or works around a refusal it should have read.

The plugin owns all versioning, lookup, policy and tagging logic. A repo keeps
only its own `docker build`, its tests, and its deploy commands. A repo's own
`AGENTS.md` records its images, deploy targets and branch rules, and may
override this skill where it says so.

**Where to read.**

| Task | Read |
| --- | --- |
| Writing a repo's build pipeline | `references/woodpecker-build.yml` |
| Writing a repo's deploy pipeline | `references/woodpecker-deploy.yml` |
| A repo on GitHub Actions | `references/github-actions.yml` |
| Every setting and its default | the plugin README at the pinned version |
| Why it is built this way | the plugin's `docs/design/standard-release.md` |

## 1. The contract

| Term | Rule |
| --- | --- |
| Version | `MAJOR.MINOR` from the manifest (`Cargo.toml`, a Go `Version` constant, `pyproject.toml`) + `PATCH`, the next number on that line from 0. The plugin claims it by creating `refs/builds/<version>` on GitHub; a failed build uses its number up, so gaps mark failed builds. |
| Build | One push pipeline = one version = one set of images, tested, then published as `<image>:<version>` only, with `org.opencontainers.image.version` and `.revision` labels. Published once, never overwritten. |
| Deploy | A Woodpecker deployment (the Deploy button, `deployment` event) to a target. It never builds: `resolve` picks the commit's tagged build, else its newest published build. |
| Git tag | Annotated `<version>`, identical to the docker tag, meaning **"this build was deployed"**. Written by `tag` once the deploy steps succeed, whatever smoke tests later find. Never moved; never a second one on a commit. |
| Order | Free: dev before prod, after it, or not at all. Whichever deploys a commit first writes the tag; every later deploy, any target, reuses that build. |
| Policy | Which targets exist and which branches may deploy to each is the repo's `environments` setting (default: `dev` from any branch, `prod` from the repo's default branch, `main` or `master`). There is deliberately no ordering option. |

The version travels between steps in `.release-tag`; every step reads
`$(cat .release-tag)`.

## 2. Never

| Never | Why |
| --- | --- |
| Create, move or delete a release tag or any `refs/builds/*` / `refs/build-pipelines/*` ref by hand | They are the record of what was built and deployed; the counter and `resolve` read them. Build refs are never pruned. |
| Set or bump `PATCH` in a manifest | The plugin owns it. The manifest carries `MAJOR.MINOR.0`. |
| Rebuild, retag or re-push an image to deploy or "fix" it | Promotion means the same bytes. A broken build is fixed by a new commit, which gets a new build. |
| Push `:latest`, `:commit-<sha>` or any second tag of an image | Lookup goes through git, not docker tags. |
| Tag on push, or tag from a build pipeline | A tag means deployed, not built or green. |
| Make `tag` wait for smoke tests | A broken deploy is still a deploy; run smoke beside `tag`. |
| Write `.release-tag` yourself in a deploy pipeline | Only `resolve` may choose what a deploy ships. |
| Put version, branch or environment logic in repo shell | That is the plugin's; add a setting or change the plugin instead. |

## 3. Operating it

- **Deploying.** A person starts deployments (Woodpecker's Deploy button on a
  green build pipeline, choosing the target) unless the repo's `AGENTS.md`
  authorises an agent to. Otherwise stop at "commit `<sha>` is built as
  `<version>` and ready to deploy to `<target>`". When a deploy runs, follow it
  with `ci-watch` like any pipeline.
- **Which version is where.** Deployed: `git ls-remote --tags origin` and match
  the commit (`git tag --points-at <sha>` after a fetch). Built:
  `git ls-remote origin 'refs/builds/*'` — the `^{}` line under each ref is the
  commit. A commit with a build ref but no tag was built, never deployed.
- **Starting an iteration.** `start-iteration` sets the manifest to `0.N.0` /
  `1.N.0`. Builds on that branch claim `0.N.x` while trunk keeps building its
  own line; both counters are independent.
- **`1.0.0`.** Set the manifest to `1.0.0` on the MVP-completion card; the
  first build after it claims `1.0.0` and its first deploy writes the tag.
  Never tag it by hand.
- **Squash merges** give trunk a new commit, so trunk needs its own build; a
  branch build that was tested on dev is not promotable to prod.

## 4. Refusals

Read the message; never work around it.

| Plugin says | Meaning | Do |
| --- | --- | --- |
| `has no published build; push a fix or re-run the build` | Every build of the commit failed before `publish` | Fix or re-run the build pipeline |
| `is not in environments` / `may not deploy to` | Target or branch outside the repo's `environments` | Deploy from an allowed branch; change `environments` only if the user asks |
| `more than one release tag` | Tagged twice under an older scheme | Report it; removing a tag is the user's decision |
| `no longer in the registry (pruned?)` | The tagged build was removed | Report it; restore the image, never rebuild the version |
| `label … want …` | An image under this version came from another build | Report it; find what pushed it |
| `already published` | Publish ran twice for one version | Report it; never overwrite |
| `already has release tag` / `tags never move` | Something other than `resolve` chose the version | Fix the pipeline so `resolve` writes `.release-tag` |
| `registry cannot answer` | Registry down or credentials wrong | Fix access; nothing is assumed missing |
| `mode compute was removed` | Pipeline still on 0.1.x settings | Migrate (§5) |

## 5. Migrating a repo

1. Read the repo's current build and deploy pipelines and release scripts; list
   what each script does and confirm the plugin covers it.
2. Set the manifest to `MAJOR.MINOR.0` (keep the current line).
3. Replace the build pipeline with `references/woodpecker-build.yml`: `version`
   first, the repo's own build and tests, `publish` last. One image entry per
   image the repo ships, each built with both labels.
4. Replace the deploy pipeline with `references/woodpecker-deploy.yml`:
   `resolve`, the repo's own deploy steps, then `tag` and smoke side by side.
   Set `environments` only if the repo differs from the default.
5. Delete the repo's release scripts and their tests, and any `:commit-<sha>`
   or `-ci` repository pushes.
6. Record images, targets and branch rules in the repo's `AGENTS.md`.
7. Prove it: run the plugin with `dry_run: true` on a branch pipeline, then a
   real build, then a dev deploy. Existing tags stay valid: a commit tagged
   under the old rule counts as already deployed.

Whatever a migration finds missing from this skill goes back into it.
