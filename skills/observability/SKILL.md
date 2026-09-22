---
name: observability
description: Observability contract for a product that runs somewhere you cannot attach a debugger - what a product must emit to be operable, why all three signals leave the process over OTLP to a collector that the product knows nothing behind, how the telemetry module is structured so exporter types never reach product code, and the cardinality rules that keep metrics affordable. Observability is part of the MVP bar, not a follow-up. Language- and backend-agnostic. Load before designing a service's telemetry, accepting OTLP from browser or mobile clients, adding or changing a metric, span, log field, dashboard or alert, taking a product to 1.0.0, or debugging why a deployed product cannot be diagnosed.
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
SDK's terms; apply it with whatever the repo uses. Where a repo's own
`AGENTS.md` or README records a deliberate deviation, that record wins.

**Terms**

- **Signal** — one kind of telemetry: **traces**, **metrics**, **logs**
  (profiles where the platform takes them). Each answers a different question
  (§3); a fact belongs in exactly one of them.
- **Resource attributes** — the identity of the emitting process, attached to
  every signal it emits: `service.name`, `service.version`,
  `deployment.environment` at minimum. They are the join key that makes one
  deployment's three signals the same deployment.
- **Collector** — the process that receives OTLP and fans telemetry out to
  backends. The single endpoint a product is configured with, and the only
  address it knows.
- **Cardinality** — the number of distinct label combinations a metric can
  produce. It is the product of its labels' value counts, and it is a cost and
  a failure mode, not a detail: one unbounded label is a metrics outage.
- **Correlation** — `trace_id` / `span_id` carried on log records and metric
  exemplars, so an alert leads to a trace and a trace leads to its logs
  without a human guessing at timestamps.
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
   `deployment.environment` — identically on every signal.
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
   (`<app>_build_info`, value `1`, labels such as `version`, `revision`) that
   queries join against (§4).
7. **One dashboard, owned by the product repo**, covering those signals, and
   **at least one symptom alert** with a runbook link
   (`references/dashboards-and-alerts.md`).
8. **Telemetry is optional at runtime** — a missing or unreachable collector
   degrades telemetry and nothing else (§6) — and **health checking is separate
   from it**, so a telemetry failure can never fail a deploy gate.

**Per iteration, decide consciously.** Every card that changes behaviour
decides whether it needs new or changed metrics, spans, log fields,
correlation, dashboards, alerts or runbook text. "No change needed" is a
decision that gets recorded; it is not the same as not having thought about it.

## 2. The egress contract

- **OTLP, and nothing else, leaves the product.** No backend-specific client,
  no vendor SDK, no pushgateway, no writing to a log file that something else
  tails. One protocol for all three signals means one thing to configure, one
  thing to test, and no backend named anywhere in product code.
- **One endpoint, configured, never compiled in.** The standard environment
  variables are the interface (`OTEL_EXPORTER_OTLP_ENDPOINT`,
  `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_SERVICE_NAME`,
  `OTEL_RESOURCE_ATTRIBUTES`), or the product's own config group mapping onto
  them. Default to gRPC (`:4317`); use `http/protobuf` (`:4318`) where gRPC is
  impractical, such as from a browser.
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
  something that **authenticates the user through the product's OIDC provider
  — never an API key or an ingest secret — enforces a per-user quota,
  rate-limits, caps the decompressed body, and overwrites what the payload
  claims about identity** — and only then re-emits into a collector that stays
  unreachable. A collector binary supplies none of those five, so it never
  faces a client directly; it sits behind something that does, whether that is
  the product itself or a service written for the job. **The endpoint is per
  service and per environment**, by default a sub-path on that service's own
  domain: the deployment that receives a span is what makes its `service.name`
  and `deployment.environment` trustworthy, because the client cannot be.
  Client telemetry is user-controlled input and is handled as such: see
  `references/client-telemetry.md` before accepting any.
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
what a span attribute already records, and never reconstruct a rate by counting
log lines. One fact, one signal, chosen by the question it answers.

## 4. Naming and cardinality

- **Use the OpenTelemetry semantic conventions** for anything they already name
  (`http.*`, `db.*`, `messaging.*`, `service.*`, `deployment.*`). Invent a name
  only for what is genuinely the product's own, and then prefix it with the
  product (`vnote.page.*`). A name matching semconv is the difference between a
  dashboard the platform's stock panels can chart and one that only this repo
  can.
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
  Export them once as an info metric (§1.6) and join.
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
  what makes swapping an SDK a one-module change.
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
- **Config is one group, validated at startup** — endpoint, protocol, service
  name, environment, log level, sampling — resolved by the same mechanism as
  the rest of the product's config, and failing loudly on a malformed value.
  **Disabled is an explicit value**, never an empty or missing one, so "off"
  and "misconfigured" are distinguishable.
- **Shutdown flushes with a bounded timeout.** The telemetry of a process that
  is going down is the telemetry most worth having, and it is lost by default.

## 6. Telemetry must never harm the product

- **A collector that is down is not an outage.** Export failures are logged
  once, at a rate limit, and never propagate to a request.
- **Never block a request on an export.** Bounded queues, background export,
  drop on backpressure, and a counter for what was dropped — telemetry that can
  exhaust memory under load is a self-inflicted incident.
- **On a client, the same rule is stricter.** A client that cannot reach its
  ingest endpoint drops the events and carries on — bounded buffer, backoff
  with jitter, retries confined to the session, nothing on the critical path,
  nothing the user ever sees. And a client with no telemetry configuration does
  not start telemetry at all: absent configuration is disabled
  (`references/client-telemetry.md`).
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
  reachable**, and with telemetry explicitly disabled;
- a request carrying inbound trace context produces a span whose parent is that
  context, asserted on **what a fake OTLP receiver received**, not on config;
- resource attributes (`service.name`, `service.version`,
  `deployment.environment`) are present on exported spans, metrics and logs;
- a log record emitted inside a span carries that span's `trace_id` and
  `span_id`;
- **no exported metric series carries a forbidden label key** — the
  identifier-cardinality test (§4), listing the keys rather than the metrics, so
  a new metric is covered without editing it;
- every enumerated attribute has a label value for **every** variant, by
  iterating the enumeration rather than listing cases;
- shutdown flushes pending spans within its timeout;
- nothing outside the telemetry module imports an SDK or exporter type;
- dashboard queries reference metric names the product actually exports, so a
  rename breaks the test rather than the dashboard.

## 8. Dashboards, alerts and the platform

Dashboards and alerts are **product artefacts**: their source lives in the
product repo, beside the metrics they chart, and ships in the same PR as those
metrics. One dashboard serves every environment, filtered by a variable, and
the repo's pipeline publishes it from trunk only.

See `references/dashboards-and-alerts.md` before adding or changing either.

**Worked examples on this machine.** `vcheesbrough/v-note` is the reference
implementation (telemetry module, span/metric conventions, cardinality test,
dashboard published by its pipeline); the platform side — collector endpoints,
the label contract it expects, retention — is `mini-config`'s
`monitoring-stack/OBSERVABILITY.md`, which is the authority for anything about
the receiving end.
