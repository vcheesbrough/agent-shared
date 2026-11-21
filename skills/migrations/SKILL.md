---
name: migrations
description: Migration contract for products deployed as containers - every change to state outside the image that a release needs (database schema, stored data, external systems such as an identity provider) runs in a one-shot migrate step from the same image before the server is replaced; the server verifies and never applies; privileged credentials reach only that step, as secret files; forward-only and compatible with the previous release. Load before adding or changing a migration, an identity-provider blueprint or other external setup a release depends on, moving migrations out of a server's startup, or writing the compose file a product deploys with.
---

# migrations

**Premise.** A release is the image *and* the state it expects: the schema,
the shape of stored data, and what it has configured in systems it does not
own. Bringing that state up to date is one step, `migrate`: a one-shot
container from the **same image**, run by every deploy before the new server
replaces the old one. The server checks that the state is current and refuses
to serve if it is not. It never changes it.

This keeps two things apart that a migrate-on-startup server mixes: the
privileges needed to change state (schema owner, an identity provider's admin
token) stay in a container that exits, and the long-running server holds only
what it needs to serve. A repo's own `AGENTS.md` records its migrate steps and
credentials, and may override this skill where it says so.

## 1. What is a migration

Any change to state outside the image that a release depends on:

| Kind | Examples |
| --- | --- |
| Schema | SQL migrations (`sqlx::migrate!`, Alembic, goose) |
| Stored data | Backfills, re-encrypting or resealing rows, rewriting a format |
| External systems | An identity-provider blueprint (Authentik application, provider, RBAC), a bucket, a queue, a topic |

Each one must be **idempotent** (a second run on current state changes
nothing), **forward-only** (no down migration), and **compatible with the
previous release** (§2 "Compatibility"). Something that cannot meet all three
is not a migration and does not go in `migrate`:

| Not a migration | Where it goes |
| --- | --- |
| Smoke or health checks, live tests | Post-deploy checks, or the promote gate in CI |
| Cache warming, notifications | The deploy pipeline or the product itself |
| A one-off repair | Run by hand, recorded on the card |
| Anything on a schedule | A timer or the product's own job runner |

## 2. The contract

| Term | Rule |
| --- | --- |
| Command | A subcommand of the product's own binary (`<bin> migrate`), in the image the server runs. No second image, no copy of the migrations or blueprint outside the image. |
| Steps | Fixed order in code: schema → stored data → external systems. Each step logs and spans as its own unit (`observability` skill: one root span per step, `error.type` on failure). |
| When | Every deploy (`docker compose up`). Not on a container restart or host reboot: it is `restart: "no"` and compose only honours `depends_on` at `up`, and state only changes when the image does. |
| Server | Waits on it: `depends_on: migrate: condition: service_completed_successfully`. At startup it **verifies**: every migration it embeds is applied, else it exits naming `migrate`. Applied migrations it does not know are tolerated; that is a rollback (below). |
| Credentials | Privileged ones (schema owner, external admin tokens) reach only `migrate`. The server never holds them. Both receive secrets as **files** (`/run/secrets/<name>`), never `environment:`: an exited container keeps its `Config.Env` in `docker inspect` until the next `up`. |
| Compatibility | Compose runs `migrate` while the old server still serves, and leaves it serving if `migrate` fails part-way. Every migration must therefore work with release N-1: expand in one release, contract (drop, rename, tighten) in a later one, once no running release reads the old shape. |
| Failure | Non-zero exit. The server is not replaced, the deploy fails, the old server keeps serving. No retry loops inside `migrate`; a transient failure is retried by re-running the deploy. |
| Rollback | Deploy the older image. Its `migrate` runs against newer state and must tolerate it (ignore unknown applied migrations, e.g. sqlx `set_ignore_missing(true)`; a re-applied older blueprint resets the fields it sets and deletes nothing). Nothing is un-applied. |
| Tests | Unit and integration tests may apply migrations directly. Assert that the server refuses a database with pending migrations. |

## 3. Never

| Never | Why |
| --- | --- |
| Apply migrations from the server's startup | It needs the privileged credentials for its whole life, and a deploy without `migrate` looks healthy |
| Apply a migration from a CI step against a live environment | The deploy is where state changes, from the image being deployed; a separate step can drift from it or be skipped |
| Pass a `migrate` credential through `environment:` | It stays readable in `docker inspect` (and Portainer) on the exited container |
| Write a down migration, or edit one already applied | Forward-only; sqlx and most tools checksum applied migrations |
| Ship a migration release N-1 cannot run against | The old server serves on the new state during every deploy |
| Put a non-idempotent action in `migrate` | It runs on every deploy, including redeploys of the same image |
| Keep the external setup (a blueprint) in the deploy repo | It is part of the release; a copy outside the image drifts |

## 4. Compose shape

```yaml
services:
  migrate:
    image: registry.example/app:1.4.2@sha256:…     # same image as server
    command: ["app", "migrate"]
    restart: "no"
    secrets: [db_owner_password, idp_admin_token, value_encryption_key]
    depends_on:
      postgres:
        condition: service_healthy

  server:
    image: registry.example/app:1.4.2@sha256:…
    restart: unless-stopped
    secrets: [db_runtime_password, value_encryption_key]
    depends_on:
      migrate:
        condition: service_completed_successfully

secrets:
  idp_admin_token:
    environment: IDP_ADMIN_TOKEN   # from the deploy's secret store, mounted as a file
  # …
```

A split database login (owner for `migrate`, read/write-only for the server)
is the full form. A product that starts with one login still runs `migrate`
separately, and splits the login later without changing the shape.

## 5. Operating it

- **Deploying** is `docker compose up -d` (through whatever wrapper the deploy
  repo uses). `migrate` runs, then the server is replaced.
- **Checking a deploy:** `docker inspect -f '{{.State.ExitCode}}'
  <migrate container>` is `0`. Its logs say which steps changed something.
- **An exited `migrate` is expected.** Smoke tests and alerts treat exit `0` as
  healthy and non-zero as a failed deploy; neither treats "not running" as down.
- **Rotating a secret** `migrate` or the server reads: compose does not
  recreate a container when only a secret's value changes, so
  `up -d --force-recreate`.
- **A failed `migrate`:** read its logs, fix forward with a new release, or
  re-run the deploy if the cause was transient. Never apply the step by hand
  against prod to get past it.

## 6. Adopting it in a repo

1. List everything the product changes outside its image: migrations run at
   startup, startup passes over data, CI steps that configure external systems.
2. Add `<bin> migrate` running them in §2's order, each idempotent, reading
   credentials from files.
3. Replace the server's apply-at-startup with verify-at-startup.
4. Move external setup (blueprints) into the image; delete the CI steps that
   applied it.
5. Add the `migrate` service and the server's `depends_on` to every compose
   file the product deploys with (dev and prod).
6. Teach the deploy repo's smoke test and pentest: `migrate` exited 0, and no
   `migrate` credential appears in `docker inspect`.
7. Record the steps and their credentials in the repo's `AGENTS.md`.

Whatever an adoption finds missing from this skill goes back into it.
