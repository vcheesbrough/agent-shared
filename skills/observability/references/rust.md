# Rust binding of the observability contract

Companion to `../SKILL.md`. Read it when the product is Rust: it names the
crates that carry the contract, the rule for pinning them, and every place the
stack's defaults would break a rule in the skill. Nothing here changes the
contract; where the stack cannot meet it, that is said, and the gap is recorded
in the product's `AGENTS.md` like any other deviation.

## The stack

One de facto set, split by who may import it. The split *is* §5's allowlist.

| Role | Crate | Imported by |
| --- | --- | --- |
| Span and log façade | `tracing` | Product code |
| Metrics façade | `opentelemetry` (the API crate; it contains no SDK) | Product code |
| Attribute-key constants | `opentelemetry-semantic-conventions` | Product code, via the shared constants module |
| Layer composition, level filter | `tracing-subscriber` | Telemetry module only |
| tracing spans → OTel spans | `tracing-opentelemetry` | Telemetry module only |
| tracing events → OTel log records | `opentelemetry-appender-tracing` | Telemetry module only |
| Providers, resource, batch processors, sampler | `opentelemetry_sdk` | Telemetry module only |
| OTLP exporters, all three signals | `opentelemetry-otlp` | Telemetry module only |
| Header inject and extract | `opentelemetry-http` | The transport layer only |

**Not in the set:** the `prometheus` crate and the `metrics` façade with its
Prometheus exporter — both are scrape, which §2 rules out;
`axum-tracing-opentelemetry` and `reqwest-tracing` — each pins its own copy of
the crates above and becomes a second pace-setter for every upgrade. Server spans are a
`tower-http` trace layer with a span factory that extracts context through
`opentelemetry-http`; outbound spans wrap the client call and inject the same
way. More code, fewer pins, and both product repos already depend on
`tower-http`.

**The allowlist test** scans `src/` for `opentelemetry_sdk`,
`opentelemetry_otlp`, `tracing_opentelemetry` and
`opentelemetry_appender_tracing` paths and fails on any outside the telemetry
module. `tracing` and `opentelemetry` are the façade and may appear anywhere.

## Pin as one set

The core crates (`opentelemetry`, `_sdk`, `-otlp`, `-http`,
`-semantic-conventions`, `-appender-tracing`) release together under one
version number. `tracing-opentelemetry` does not: it has its own number and it
lags. **It sets the pace.** The workspace pins the whole set to whatever
`tracing-opentelemetry` requires, in one place, and moves it as one.

Never infer a pairing from a version number: the log bridge shares the core's
number, the span bridge does not, and on 2026-09-23 the two were both at
`0.33` while requiring different cores. To find the consistent set, read the
`opentelemetry` requirement of the newest `tracing-opentelemetry` release on
crates.io, and take the core family at that version. On that date the set was
core `0.32` with `tracing-opentelemetry` `0.33`; the core's `0.33` had shipped
five days earlier and was unusable until the span bridge caught up.

## How each signal leaves

One `Resource`, built once and passed to all three providers, so §1.2 holds by
construction. It is the environment detector (reads `OTEL_SERVICE_NAME` and
`OTEL_RESOURCE_ATTRIBUTES`) plus `service.version` from the build, which the
variables cannot override, and `service.instance.id` as a version 5 UUID of
the container hostname (§4; the `uuid` crate does this) unless the variables
already carry it (§5). **No host or process
detectors**: they add values such as the process id that change on every
restart, which is the instance-id mistake in another form.

### Which variables the SDK reads, and which the module must

The contract is the `OTEL_*` variables (§2). The Rust SDK implements some of
them and silently ignores the rest, so the module reads those itself. As of
the `0.32` set — re-verify against the pinned version's docs when it moves:

| Read by the SDK | Where |
| --- | --- |
| `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES` | the resource builder's environment detector |
| `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`, `OTEL_EXPORTER_OTLP_TIMEOUT`, and `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`, `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT`, `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` | the OTLP exporter builders |
| `OTEL_TRACES_SAMPLER`, `OTEL_TRACES_SAMPLER_ARG` | the tracer provider's default config |
| `OTEL_BSP_MAX_QUEUE_SIZE`, `OTEL_BSP_SCHEDULE_DELAY`, `OTEL_BSP_EXPORT_TIMEOUT`, `OTEL_BSP_MAX_EXPORT_BATCH_SIZE`, and the same four with `OTEL_BLRP_` | the batch span and log processors |
| `OTEL_METRIC_EXPORT_INTERVAL`, `OTEL_METRIC_EXPORT_TIMEOUT` | the periodic metric reader |

| Read by the module, because the SDK does not | Effect |
| --- | --- |
| `OTEL_SDK_DISABLED` | `true`: install the `fmt` layer and nothing else |
| `OTEL_TRACES_EXPORTER`, `OTEL_METRICS_EXPORTER`, `OTEL_LOGS_EXPORTER` | `none` skips that signal's provider; anything but `otlp` or `none` fails startup |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | the transport is a builder choice (`with_http` or `with_tonic`), so the module picks it from the value, `http/protobuf` when unset |
| `OTEL_PROPAGATORS` | the module installs the W3C trace-context propagator; any other value fails startup |
| `OTEL_EXPORTER_OTLP_ENDPOINT` absent while any other `OTEL_*` variable is set and a signal exports | startup failure, never the SDK's localhost default (§2); with no `OTEL_*` variable at all, telemetry is off |

The startup validation in §5 runs over both tables before any provider is
built, so a value the SDK would have shrugged at is a failure the deploy sees.

- **Traces.** `tracing` spans → the span layer → the SDK tracer provider with
  a batch processor → the OTLP span exporter over `http/protobuf`, the spec's
  default. Sampler: parent-based
  over a trace-id ratio from config, default everything (§2: sampling is the
  collector's).
- **Logs.** `tracing` events → the log bridge layer → the SDK logger provider
  with a batch processor → the OTLP log exporter. Plus a `fmt` layer to stdout
  for `docker logs`; whether the platform ships that stdout is the platform's
  decision (§2), not a reason to drop it.
- **Metrics.** The `opentelemetry` API's global meter → the SDK meter provider
  with a periodic reader → the OTLP metric exporter. Cumulative, which is the
  default. Instruments are created once, in the telemetry module or a
  metrics module beside it, held in statics, and exposed to product code as
  typed handles — never created per request.

**Off is the absence of the variables.** With no `OTEL_*` variable set, or
with `OTEL_SDK_DISABLED=true`, the module installs the `fmt` layer, the W3C
propagator and nothing else: no providers, no exporters, no background
threads, and one line at startup saying telemetry is off. The transport
layer's extraction and injection run regardless, so a silent service still
passes trace context through (`../SKILL.md` §2). `cargo run` and `cargo test` therefore need
nothing set. A signal is silenced on its own with its exporter variable at
`none`, in which case its provider is not built either. The product's own log
level (`RUST_LOG`, or the product's equivalent) is the one setting outside the
`OTEL_*` family, and it reaches only the `fmt` and log-bridge layers (*Layer
order and filters*).

## Layer order and filters

The defaults break three rules of the skill. The module fixes all three:

- **The span layer sees spans only.** By default it also records every
  `tracing` event as a span event, while the log bridge turns the same event
  into a log record — one fact, twice (§3). Give the span layer a filter that
  passes only span metadata. Events then reach logs and stdout; spans carry
  attributes.
- **The level filter never touches the span layer.** The product's log-level
  knob (and `RUST_LOG`) filters the `fmt` and log-bridge layers. A filter at
  `warn` on the whole subscriber drops every span the product would have
  produced, silently.
- **The SDK's own events stay out of the export path.** Export failures are
  reported through the SDK's internal logging on its own target. Keep that
  target at `warn` on the stdout layer, where it is the failure signal §6 asks
  for, and filter it out of the log-bridge layer, so a failing export can
  never produce a log record that fails to export.

And one option to leave alone: the log bridge can copy the enclosing span's
attributes onto every log record. Off, or an allowlist of one or two keys a
log query genuinely needs. Wholesale copying is "log what the span already
records" (§3).

## Attribute keys

`tracing` macros take field names as literals at the call site; a constant
cannot be a span-creation key. So:

- **Literals are allowed inside the macros**, and nowhere else. Attributes set
  after creation use the span extension's `set_attribute` with a constant from
  `opentelemetry-semantic-conventions`; metric attributes are `KeyValue`s
  built from the same constants.
- **The test guards the export, not the source.** Collect every span attribute
  key an in-memory exporter received and assert each is a semantic-convention
  name or carries the product prefix (§7). A typo in a literal fails the
  test, which is the point.
- **Span kind, name and status** are the span bridge's reserved fields
  (`otel.kind`, `otel.name`, `otel.status_code`), also literals.

## Propagation

Two contexts exist, and confusing them is the commonest silent failure: the
`tracing` span is what is current in product code, and the OpenTelemetry
context is derived from it.

- **Inbound**, in the transport layer: extract with the global propagator from
  the request headers through `opentelemetry-http`, then set the extracted
  context as the new span's parent through the span extension. The global
  propagator is the W3C trace-context one, installed by the module.
- **Outbound**, in the transport layer: take the context *from the current
  `tracing` span* through the span extension and inject it into the request
  headers. Never read the SDK's own current context in product code: it is
  empty unless the span layer has activated it, and an empty context injects
  nothing without an error.
- **Spawned tasks** lose the span unless it is carried explicitly with
  `tracing`'s `Instrument`. A task spawned without it starts a fresh, orphaned
  trace.
- **Detached work** starts a new root span and adds a link to the span that
  queued it, through the span extension (§5).

## Metrics specifics

- **Histogram boundaries are set at instrument creation, in seconds.** The
  SDK's default boundaries suit milliseconds; semantic-convention durations
  are seconds, and a seconds histogram on the default boundaries puts every
  request in the first bucket. Use the boundaries the convention recommends
  for `http.server.request.duration`.
- **Labels come from exhaustive matches** (§4), as `KeyValue`s of constants and
  the variant's label value.
- **The SDK caps series per instrument** (a default of two thousand, with the
  overflow marked on an attribute). That is a backstop that keeps a mistake
  from becoming a bill; the forbidden-label test remains the rule.
- **Build info** is one gauge set to `1` once, with version and revision as
  attributes of that instrument only. Everything else's identity is the
  resource, and which resource attributes become series labels is the
  collector's decision (§4).
- **No exemplars.** The Rust SDK does not implement them. Metric-to-trace
  correlation here is by time range and labels, and nothing should be written
  as if it were otherwise.

## Shutdown and failure

- **Shut down inside the runtime.** The exporter's HTTP client needs the async
  runtime alive to flush. The module's shutdown calls each provider's `shutdown`
  before the runtime is dropped, and the batch processors' export timeouts
  bound how long that can take (§5).
- **An unreachable collector costs nothing at startup.** Nothing connects
  until the first batch; the process serves; batches are dropped when the bounded
  queue fills, and the SDK says so on its own log target at most once per
  export interval — which is the rate limit §6 asks for, at no cost.
- **The SDK exports nothing about itself.** There is no counter of dropped
  spans or failed batches to alert on. Either wrap the exporter to count and
  export it, or record the gap in `AGENTS.md`. One or the other, written down.

## Tests

The SDK's `testing` feature provides in-memory exporters for all three
signals. The module takes its exporters as parameters, so the tests build the
same module with in-memory ones and assert on what was received:

- parent from inbound context; resource attributes on every signal; `trace_id`
  and `span_id` on a log record emitted inside a span; the forbidden-label
  keys; the attribute-key check above; the every-variant check; shutdown
  flushes (§7);
- the no-collector test runs the real module against an endpoint nothing
  listens on and asserts the product still serves and exits in bounded time;
  the no-variables test runs it with an empty environment and asserts the
  same, plus the one startup line;
- the allowlist test scans the source tree (above).

## Browsers and WASM

The OpenTelemetry crates do not build for `wasm32`. A Rust SPA has no crate to
adopt: it hand-rolls OTLP/JSON over `fetch` with the bounded buffer and the
failure rules of `client-telemetry.md`, or binds the JavaScript SDK through
`wasm-bindgen`. Either way that reference applies unchanged; this one does
not.
