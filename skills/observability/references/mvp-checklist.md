# Observability sign-off and retrofit order

Companion to `../SKILL.md`. Read it when a product is approaching `1.0.0`
(baseline §2) or when an existing product has to be brought up to the bar.

## Signing the MVP off

The MVP-completion card does not merge until each line of `../SKILL.md` §1 has
an answer of the form *"here is where it is done, and here is what shows it
working"*. Evidence is a test, a query or a screenshot of a live panel — not an
assertion that the code calls a tracing library.

| Bar (§1) | Evidence that settles it |
| --- | --- |
| 1. All three signals over OTLP | The fake-receiver test; the configured endpoint in the deployed environment |
| 2. Resource attributes | The exported-attributes test; one query per signal filtered on `service.name` |
| 3. Spans at every entry point and process boundary | A trace of one real request, showing the edge span, the product's span and its database/HTTP children |
| 4. Structured, correlated logs | A log line for that same request, found by its `trace_id` |
| 5. RED + saturation | The dashboard panels, non-empty, under real traffic |
| 6. Build info metric | A query joining a working metric to `<app>_build_info` |
| 7. Dashboard and one symptom alert | The published dashboard uid; the alert rule and its runbook link |
| 8. Telemetry optional, health separate | The no-collector test; the deploy gate's health check, with no telemetry dependency |

Record the answers in the card or the repo's deploy doc. A gap that is
deliberate is recorded with its reason and what would close it — the same rule
as an uncovered behaviour in baseline §6.

## Retrofitting an existing product

Order matters: each step is usable on its own, and each makes the next one
cheaper. Do not start with dashboards — a dashboard over uncorrelated signals
is a picture of the problem.

1. **Resource attributes and the telemetry module.** Create the module, set
   `service.name` / `service.version` / `deployment.environment`, wire the OTLP
   exporter and a bounded, flushing shutdown. Nothing else changes yet. From
   here, every later step lands already identified and already correlated.
2. **Logs through the module.** Move existing logging onto the façade the
   module configures, structured, with trace/span ids attached when a span is
   in scope. Existing log statements keep working; they gain correlation.
3. **Spans at the entry points**, then at the process boundaries (database,
   outbound HTTP, queue). Adopt inbound trace context here, so the product
   joins traces that already start at the edge router rather than starting its
   own.
4. **RED metrics** derived from the entry-point spans' own instrumentation
   points, plus saturation metrics for pools and queues. Add the
   forbidden-label test in the same change, before there is a cardinality
   problem to unpick.
5. **The build-info metric**, once there is anything to join it to.
6. **Dashboard, then alerts** (`dashboards-and-alerts.md`). Alerts last,
   because an alert on a metric whose shape is still changing trains everyone
   to ignore it.

## Rolling back a signal

A signal that costs more than it is worth may be dropped, and dropping one is a
product change like any other: remove the instrumentation, remove the panels
and alerts that read it, and record in the repo why it went. What is not
acceptable is leaving a dashboard panel or an alert rule querying a metric the
product no longer exports — a silent panel reads as a healthy one.
