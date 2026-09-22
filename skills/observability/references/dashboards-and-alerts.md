# Dashboards and alerts

Companion to `../SKILL.md` §8. Read it before adding or changing either.

## Ownership

**The product repo owns them.** Dashboard JSON and alert rules live beside the
code that exports the metrics they read, and ship in the **same PR** as those
metrics — a metric added without its panel is a metric nobody finds, and a
panel added later has no reviewer who remembers what the metric means.

The platform repo owns only infrastructure dashboards (host, collector,
storage). A product never edits those, and never adds a per-product scrape job
or rule file to the platform's config when a labelling contract can carry it.

## Publishing

- **Publish from the product's trunk pipeline only** — not per branch, not per
  environment deploy. Otherwise a feature branch, or a rollback to an older
  release, silently overwrites the shared dashboard.
- **One dashboard for every environment**, filtered by a template variable over
  `deployment.environment`. Two near-identical dashboards diverge within a
  month.
- **Give each dashboard a stable uid** and set the publish message to the
  release and commit, so the backend's version history traces back to a source
  revision.
- **Edits made in the UI are overwritten by the next publish.** That is the
  intended behaviour; export an experiment back into the repo or lose it.
- The publish credential is a narrowly scoped service account with write access
  to the product's folder and nothing else. It is never a personal token and
  never an admin one.

## Designing the dashboard

Top row answers "is it healthy?" in one screen: request rate, error rate,
latency percentiles, saturation of the tightest resource. Everything below is
for the person who has already decided something is wrong.

- Percentiles from histograms, never averages — an average latency hides
  exactly the users who are suffering.
- Every panel a query a human could have written; no panel whose meaning
  depends on knowing which deploy it was built for.
- Link from the dashboard to traces and logs for the same selection, so the
  path from symptom to cause is a click and not a retyped query.

## Designing alerts

- **Alert on symptoms, not causes.** Errors visible to users, latency past a
  threshold a user would notice, unavailability. A cause alert (pool near
  capacity, disk filling) fires when nothing is wrong yet and trains its
  audience to ignore it; prefer a dashboard panel, or a low-urgency alert that
  reaches nobody at night.
- **Every alert has a runbook link** naming what to check first and what a
  false positive looks like. An alert with no runbook is a page with no plan.
- **Every alert has an owner and an urgency.** If nobody would get out of bed
  for it, it is not a page.
- **Telemetry's own failures are not product alerts.** A collector outage is
  the platform's alert, and the product's alerts should be written knowing they
  go blind during one — which is itself a reason not to build a deploy gate on
  telemetry (`../SKILL.md` §6).
- Alert thresholds are reviewed after each incident they did, or should have,
  caught. An alert that has never fired and an alert that fires weekly are both
  suspect.
