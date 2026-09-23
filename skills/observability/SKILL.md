---
name: observability
description: Observability contract for products that run where you cannot attach a debugger - what to emit, OTLP egress, the telemetry module, cardinality, and the MVP bar. Load before designing or changing telemetry, choosing or upgrading telemetry crates, accepting OTLP from browser or mobile clients, adding a metric, span, log field, dashboard or alert, taking a product to 1.0.0, or debugging an undiagnosable deployment.
---

# observability

**Premise.** When a deployed product misbehaves, an operator has only what the
process already emitted. Instrumentation cannot be added to an event that has
already passed, so observability is built with the feature, not after it: a
product that cannot be diagnosed in production is not finished, whatever its
features do. **Every product reaches its MVP (`1.0.0`, baseline §2) only with
the bar in §1 met** — pre-MVP iterations may leave parts of it unbuilt, but the
release that crosses to `1.0.0` may not.

The second premise is separation: a product must not know which backend stores
its telemetry. **OTLP is the only egress**, to one collector endpoint, and
everything behind that endpoint — Tempo, Loki, Prometheus, a vendor, nothing at
all — is the platform's business and can be replaced without a product change.

This is a design contract, not a library. It is stated in no language's or
SDK's terms; apply it with whatever the repo uses. Where a language has a
settled stack, a reference binds the contract to it and records where that
stack falls short. Where a repo's own `AGENTS.md` or README records a
deliberate deviation, that record wins.

**Where to read.** This file is the contract for a server process. Load a
reference only for the task it names:

| Task | Read |
| --- | --- |
| Sending telemetry from a browser, phone or desktop client | `references/client-export.md` |
| Building or operating the endpoint that accepts client telemetry | `references/client-ingest.md` |
| A Rust product: crates, pinning, what the SDK reads, where it falls short | `references/rust.md` |
| Wiring the variables through sovereign-config on this estate | `references/deployment.md` |
| Adding or changing a dashboard or alert | `references/dashboards-and-alerts.md` |
| Signing off `1.0.0`, or retrofitting an existing product | `references/mvp-checklist.md` |

**Terms**

- **Signal** — one kind of telemetry: **traces**, **metrics**, **logs**
  (profiles where the platform takes them). Each answers a different question
  (§3); a fact belongs in exactly one of them.
- **Resource attributes** — the identity of the emitting process, attached to
  every signal it emits: `service.name`, `service.version`,
  `deployment.environment.name` at minimum. They are the join key that makes
  one deployment's three signals the same deployment.
- **Collector** — the process that receives OTLP and fans telemetry out to
  backends. The single endpoint a product is configured with, and the only
  address it knows.
- **Cardinality** — the number of distinct label combinations a metric can
  produce. It is the product of its labels' value counts, and it is a cost and
  a failure mode, not a detail: one unbounded label is a metrics outage.
- **Correlation** — `trace_id` / `span_id` carried on log records, and on
  metric exemplars where the SDK supports them, so an alert leads to a trace
  and a trace leads to its logs without a human guessing at timestamps.
- **Symptom alert** — an alert on something a user would notice (errors,
  latency, unavailability), as opposed to a cause alert on a machine-level
  condition that may or may not matter.

## 1. The MVP bar

A product is observable enough to release when **all** of these hold. Each is
checkable; `references/mvp-checklist.md` has the sign-off procedure and the
order to retrofit them in when a product is already part-built.

1. **All three signals leave the process over OTLP** to a configured collector
   endpoint (§2).
2. **Resource attributes are set** — `service.name`, `service.version`,
   `deployment.environment.name` — identically on every signal.
3. **Every entry point opens a span**: each inbound request, message or
   scheduled job. Incoming trace context is adopted, outgoing context is
   propagated, and every call that leaves the process (database, HTTP, queue)
   is a child span.
4. **Logs are structured**, emitted through the same pipeline, and every record
   written inside a span carries that span's `trace_id` and `span_id`.
5. **RED metrics for every entry point** — rate, errors, duration (as a
   histogram, not an average) — and a **saturation** metric for every bounded
   resource the product owns: connection pool, work queue, buffer, semaphore.
6. **Build identity is queryable without being a label** — an info metric
   (`<app>.build.info`, value `1`, attributes such as `version`, `revision`;
   stored as `<app>_build_info` after the platform's translation) that queries
   join against (§4).
7. **One dashboard, owned by the product repo**, covering those signals, **at
   least one symptom alert** with a runbook link, and **the absence alert** on
   the build-info gauge that stands in for `up` under push
   (`references/dashboards-and-alerts.md`).
8. **Telemetry is optional at runtime** — no `OTEL_*` variables means no
   telemetry and nothing else changes, an unreachable collector degrades
   telemetry and nothing else (§6), and only a half-configured set is a fault
   that fails startup (§2) — and **health checking is separate from it**, so a
   telemetry failure can never fail a deploy gate.

**Per iteration, decide consciously.** Every card that changes behaviour
decides whether it needs new or changed metrics, spans, log fields,
correlation, dashboards, alerts or runbook text. "No change needed" is a
decision that gets recorded; it is not the same as not having thought about it.

## 2. The egress contract

- **OTLP, and nothing else, leaves the product.** No backend-specific client,
  no vendor SDK, no pushgateway, no writing to a log file that something else
  tails. One protocol for all three signals means one thing to configure, one
  thing to test, and no backend named anywhere in product code.
- **Metrics are pushed too, not scraped.** Scrape is the older habit and it is
  tempting on an internal network, but it splits identity — the scraper labels
  metrics from the deployment while the process labels its traces and logs —
  and it cannot serve a job that exits, which §1.3 counts as an entry point.
  Push keeps one identity source for every signal, can carry trace exemplars
  where the SDK supports them, and opens no listening port for a side purpose. What scrape
  supplied for free is supplied by rule instead: a stable instance id (§4) and
  an absence alert in place of `up` (§1.7). Temporality is **cumulative**, and
  it is not a product choice: a backend that wants delta gets it from the
  collector.
- **The standard `OTEL_*` environment variables are the whole configuration
  interface, in every language.** A product has no telemetry section in its
  own config: the deployment sets the variables, the SDK reads the ones it
  implements, and the telemetry module reads the rest (§5). One vocabulary
  across every product means a deployment is configured the same way whatever
  the language, and no repo invents a second name for a knob that already has
  one:
  - identity — `OTEL_SERVICE_NAME`, and `OTEL_RESOURCE_ATTRIBUTES` for
    `deployment.environment.name` and anything else only the deployment
    knows;
  - egress — `OTEL_EXPORTER_OTLP_ENDPOINT`, one value for all three signals,
    and `OTEL_EXPORTER_OTLP_PROTOCOL`: `http/protobuf` (`:4318`), the spec's
    default, for servers and clients alike; `grpc` (`:4317`) only where
    something already speaks it;
    `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`, `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT`
    and `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` only when one signal genuinely goes
    elsewhere;
  - sampling — `OTEL_TRACES_SAMPLER=parentbased_traceidratio` with
    `OTEL_TRACES_SAMPLER_ARG`;
  - off — `OTEL_SDK_DISABLED=true` for everything; `OTEL_TRACES_EXPORTER`,
    `OTEL_METRICS_EXPORTER`, `OTEL_LOGS_EXPORTER`, each `otlp` by default and
    `none` to silence that one signal;
  - queues and intervals — `OTEL_BSP_MAX_QUEUE_SIZE`,
    `OTEL_BSP_SCHEDULE_DELAY`, `OTEL_BSP_EXPORT_TIMEOUT`,
    `OTEL_BSP_MAX_EXPORT_BATCH_SIZE`, the same four for log records with
    `OTEL_BLRP_` in place of `OTEL_BSP_`, and `OTEL_METRIC_EXPORT_INTERVAL`,
    `OTEL_METRIC_EXPORT_TIMEOUT`; all left at their defaults until a
    measurement says otherwise.
- **Absent is off; half-present is a fault; localhost is neither.** With no
  `OTEL_*` variable set at all, telemetry is off and the process runs exactly
  as it otherwise would — which is how it runs on a laptop, in tests and in
  CI — saying so once at startup so "why are there no spans" has an answer.
  With any of them set, the module validates the whole set, and a missing
  endpoint fails startup while any signal still exports. SDKs default a
  missing endpoint to localhost, which is a compiled-in address by another
  name, and the module never lets that default apply. `OTEL_SDK_DISABLED=true`
  remains the explicit off for a deployment that carries the variables and
  wants them silent; `OTEL_TRACES_EXPORTER`, `OTEL_METRICS_EXPORTER` and
  `OTEL_LOGS_EXPORTER` set to `none` silence one signal each. Off never
  touches propagation: the transport layer still extracts inbound trace
  context and injects it outbound, as the spec requires of a disabled SDK, so
  a silent service does not break the trace passing through it. What makes a
  silent default safe in production is §1.7's absence alert: a deployment that
  should report and does not is noticed, whether it lost its variables or its
  process.
- **On this estate the variables arrive through sovereign-config**, in a layer
  of their own per product environment, with facts shared across products
  stored once and aliased: `references/deployment.md`. Recommended, not
  required by the contract.
- **The product knows nothing behind the collector.** It does not know which
  store receives a signal, nor the retention, nor whether the collector
  samples. Changing backends is a platform change with no product release.
- **Egress is internal; ingest may not be.** The product's own export — server
  process to collector — never crosses a public network, and collector ports
  and any scrape endpoint stay off the public router. **Telemetry arriving from
  a user's device is the other direction**, and a product whose clients run on
  phones and browsers has to accept it publicly. That path is a public API,
  with everything that implies, not an open collector port.
- **Clients never terminate against a collector.** Client telemetry lands on
  an ingest that authenticates the user through the product's OIDC provider,
  is rate-limited and body-capped at the edge, overwrites what the payload
  claims about identity, and only then re-emits into a collector nothing else
  can reach — one ingest-and-collector pair per product environment. Client
  telemetry is user-controlled input: `references/client-ingest.md` is the
  contract for accepting it, `references/client-export.md` for sending it.
- **Deviations are recorded.** A platform that can only scrape (a Prometheus
  `/metrics` endpoint) or can only collect stdout gets that written down in the
  repo's `AGENTS.md`, with what it would take to move to OTLP. A product built
  before this contract is grandfathered by that record, not by silence; new
  products push OTLP.

## 3. What each signal is for

Each signal answers a different question, and the cheapest way to make
telemetry unaffordable is to answer one signal's question with another's.

- **Traces — "what happened in this one request?"** The primary signal.
  Structure, causality and timing, with the detail on span attributes, which
  may be as specific as the request is (ids, routes, sizes). High cardinality
  is free here, because nothing aggregates it.
- **Logs — "what did the code have to say at this moment?"** Structured
  records, joined to a trace by `trace_id`. What a log says that a span cannot:
  a message meant for a human, and events outside any span (startup, config
  resolution, shutdown).
- **Metrics — "what is happening in aggregate, over time?"** The signal alerts
  and dashboards are built on. Bounded label sets, always (§4). A metric is a
  time series, not an event log: if a fact is per-request, it belongs on a
  span.

**Consequences.** Never emit a metric to carry per-request detail, never log
what a span attribute already records, never let one event become both a span
event and a log record, and never reconstruct a rate by counting log lines.
One fact, one signal, chosen by the question it answers.

## 4. Naming and cardinality

- **Use the OpenTelemetry semantic conventions** for anything they already name
  (`http.*`, `db.*`, `messaging.*`, `service.*`, `deployment.*`). Invent a name
  only for what is genuinely the product's own, and then prefix it with the
  product (`vnote.page.*`). A name matching semconv is the difference between a
  dashboard the platform's stock panels can chart and one that only this repo
  can. **A name the estate sets across products** — the path marker
  `telemetry_source`, with values `docker`, `file`, `otlp` and `client` — is
  a bare snake_case key with no namespace. That is a deliberate departure
  from semconv's recommendation of a reverse-domain prefix for such names,
  taken to keep labels short and queries readable, and recorded here as the
  deviation it is. Never an invented name inside a namespace semconv owns
  (`telemetry.*`, `otel.*`).
- **Every metric label's value set is bounded by an enumeration in code.** The
  label comes from an exhaustive match over a type, so adding a variant fails
  to build until it is given a label value, and a label can never carry a value
  no one predicted.
- **Identifiers are never metric labels, and never stream labels on logs.**
  User, session, request, correlation, trace, span, entity and tenant ids;
  routes with unbounded parameters; anything derived from user input. They live
  in span attributes and log fields, where they cost nothing and are
  searchable.
- **Build identity is never a label on a working metric.** Version, revision
  and protocol change on every deploy, and each new value starts a new series.
  Export them once as an info metric (§1.6) and join. Under push this needs
  the collector's cooperation, because `service.version` rides on every
  metric's resource (§1.2): the collector promotes `service.name`,
  `deployment.environment.name` and `service.instance.id` to series labels and
  nothing else, and the rest of the resource reaches the store only through
  the target-info series. That is a platform rule, recorded on the receiving
  end.
- **`service.instance.id` is stable and unique per replica, or absent.** Once
  metrics are pushed it is what tells two replicas' series apart, and it rides
  on every one of them. Take it from the container hostname or an equivalent
  that survives a restart — never a random value per start, which is a new set
  of series on every restart, the same mistake as a version label; never absent
  where replicas exist, which merges their series into one. Derive it the way
  the semantic conventions ask of a stable source: a version 5 UUID of the
  hostname under semconv's namespace UUID, so the value is stable and unique
  and the hostname itself is not published.
- **Enforce it with a test, not with care.** One test collects everything the
  product exports and fails if any metric series carries a forbidden label key
  (§7). Cardinality mistakes are invisible in review and obvious in a bill.
- **Errors are typed, not stringly.** An `error_class` or `error.type`
  attribute drawn from an enumeration; the message and any detail go in the log
  record or span, not the label.

## 5. How a product implements it

One module owns telemetry; the rest of the product does not know it exists:

```
product code ──► the language's logging / span / metric façade
                 (no SDK type, no exporter type, no attribute-key literal
                  outside a shared constant)
                               │
                    telemetry module  ── init: resource attributes, sampling,
                               │          exporters, propagators
                               │      ── shutdown: flush, bounded timeout
                               ▼
                             OTLP
                               │
                          collector ──► whatever the platform stores it in
                                        (the product never names these)
```

- **The telemetry module is the only place SDK and exporter types appear.**
  Product code emits through the language's façade. Enforce it mechanically: a
  lint or test that fails when anything else imports the SDK or exporter
  packages, with the telemetry module as its only allowlisted importer. This is
  what makes swapping an SDK a one-module change. Where the façade's macros
  accept only literal keys, the literal is allowed at that call site, and a
  test checks every exported attribute key against the shared constants
  instead (§7).
- **Instrument boundaries, not lines.** A span per entry point, a span per call
  that leaves the process, a span per unit of work a human would name. Spans
  inside pure computation are noise; if a hot path needs timing, that is a
  histogram.
- **Context propagation belongs to the transport layer.** Extraction from an
  inbound request and injection into an outbound one happen in the same layer
  that speaks the protocol. Business logic inherits the ambient context and
  never passes trace ids as parameters.
- **Detached work gets its own trace, linked to what queued it.** A job that
  outlives its request is not a child span of that request — the request's
  trace would never close. Start a trace and add a link.
- **The span macro or helper is where the call site is captured**, so
  code-location attributes name the caller and not the telemetry module.
- **Config is the `OTEL_*` variables, validated at startup.** The SDK reads
  the variables it implements and the module reads the rest — which is which
  is SDK-specific and recorded in the language binding — and, when any of
  them is present, the module validates the set as a whole before anything
  starts: an endpoint that is a URL whenever a signal exports, a protocol that
  is one of the two, a sampler argument in range, the required resource
  attributes present. A malformed value fails startup loudly; left to
  themselves, SDKs ignore one and fall back to a default. With none present,
  nothing is validated because nothing starts (§2).
  **Two facts are not the deployment's to state.** `service.version` is the
  build's, set by the module and not overridable, because an environment can
  be stale and a binary cannot; `service.instance.id` is the host's (§4), set
  by the module unless the variables already carry it. **The one knob outside
  the family is the product's own log level**, by the language's convention,
  and it filters logs only, never spans.
- **Shutdown flushes with a bounded timeout.** The telemetry of a process that
  is going down is the telemetry most worth having, and it is lost by default.

## 6. Telemetry must never harm the product

- **A collector that is down is not an outage.** Export failures are logged
  once, at a rate limit, and never propagate to a request.
- **Never block a request on an export.** Bounded queues, background export,
  drop on backpressure, and a counter for what was dropped — telemetry that can
  exhaust memory under load is a self-inflicted incident.
- **On a client, the same rule is stricter**: drop and carry on, bounded
  buffer, retries confined to the session, nothing the user ever sees, and no
  telemetry at all without configuration from the product
  (`references/client-export.md`).
- **Never in the health gate.** Readiness and liveness checks, deploy smoke
  tests and CI gates do not depend on telemetry reaching anything.
- **No secrets, credentials, tokens or payloads.** Not in span attributes, not
  in log fields, not in error messages. Query *names* and call sites, never SQL
  text or bound values; identifiers, never the content they identify. Telemetry
  leaves the process and lands somewhere with different access control — treat
  it as published.
- **Telemetry is operational data.** It is not a durable record, not an audit
  log, and not backed up. Anything that must survive belongs in the product's
  own storage.

## 7. Tests that protect the contract — do not weaken them

- the product starts, serves and shuts down normally with **no collector
  reachable**, with **no `OTEL_*` variable set**, and with
  `OTEL_SDK_DISABLED=true`;
- a request carrying inbound trace context produces a span whose parent is that
  context, asserted on **what a fake OTLP receiver received**, not on config;
- resource attributes (`service.name`, `service.version`,
  `deployment.environment.name`) are present on exported spans, metrics and
  logs;
- a log record emitted inside a span carries that span's `trace_id` and
  `span_id`;
- **no exported metric series carries a forbidden label key** — the
  identifier-cardinality test (§4), listing the keys rather than the metrics, so
  a new metric is covered without editing it;
- every enumerated attribute has a label value for **every** variant, by
  iterating the enumeration rather than listing cases;
- every exported span attribute key is a semantic-convention name or carries
  the product prefix, collected from what a fake receiver received, so a key
  typed as a literal at a call site is still checked;
- shutdown flushes pending spans within its timeout;
- nothing outside the telemetry module imports an SDK or exporter type;
- dashboard queries reference metric names the product actually exports — as
  the platform stores them, after its translation of units and separators — so
  a rename breaks the test rather than the dashboard.

## 8. Dashboards, alerts and the platform

Dashboards and alerts are **product artefacts**: their source lives in the
product repo, beside the metrics they chart, and ships in the same PR as those
metrics. One dashboard serves every environment, filtered by a variable, and
the repo's pipeline publishes it from trunk only.

See `references/dashboards-and-alerts.md` before adding or changing either.

**There is no reference implementation.** No product on this machine yet meets
§1 in full, and none is to be copied as if it did — including `v-note`, whose
telemetry predates this contract and exports only traces over OTLP. Apply the
contract, not a repo. The platform side — collector endpoints, the label
contract it expects, retention — is `mini-config`'s
`monitoring-stack/OBSERVABILITY.md`, which is the authority for the receiving
end and nothing else: where it tells an application what to emit, this skill
wins for new work, and the difference is recorded as a deviation (§2).
