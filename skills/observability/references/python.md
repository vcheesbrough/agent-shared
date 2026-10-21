# Python binding of the observability contract

Companion to `../SKILL.md`. Read it when the product is Python: it names the
packages that carry the contract, the rule for pinning them, and every place
the SDK's defaults would break a rule in the skill. Nothing here changes the
contract; where the stack cannot meet it, that is said, and the gap is recorded
in the product's `AGENTS.md` like any other deviation.

Worked example: **code-vitals** (`src/code_vitals/telemetry.py`, `obs.py`,
`tests/test_telemetry_*.py`), a short-lived CLI job. Everything below was
checked against `opentelemetry-python` 1.45.1 and this estate's `monitor-alloy`
on 2026-10-21.

## The stack

| Package | Who may import it |
| --- | --- |
| `opentelemetry-api` (`opentelemetry.trace`, `.metrics`, `._logs`) | anyone — it is the façade |
| `opentelemetry-sdk` (`opentelemetry.sdk.*`) | the telemetry module only |
| `opentelemetry-exporter-otlp-proto-http` (`opentelemetry.exporter.*`) | the telemetry module only |
| `opentelemetry-proto` | tests (the fake receiver) |

Logs are emitted with the standard library's `logging`, not the OTel logs API;
the SDK's `LoggingHandler` bridges them. Enforce the split with a test that
parses every source file and fails on an `opentelemetry.sdk` / `.exporter`
import outside the telemetry module.

Ship the **HTTP exporter only**: `http/protobuf` is the contract's default, and
leaving out `opentelemetry-exporter-otlp-proto-grpc` keeps grpcio out of the
image. The module then rejects `OTEL_EXPORTER_OTLP[_<SIGNAL>]_PROTOCOL` other
than `http/protobuf` at startup rather than silently ignoring it.

## Pin as one set

`opentelemetry-api`, `-sdk`, `-exporter-otlp-proto-http` and `-proto` release
together under one version (1.45.1 at the time of writing): pin all four
exactly, to the same version, and bump them together. The contrib
instrumentations (`opentelemetry-instrumentation-*`) version separately and
are still `0.x b` releases — see *Instrumentation* below before adding one.

## How each signal leaves

Build the providers by hand in the telemetry module; do not use the SDK's
auto-configuration (`opentelemetry-instrument`, `OTEL_PYTHON_*` configurators):
it reads variables the module must validate, and it cannot express the rules
below.

- **Traces**: `TracerProvider(resource=…, shutdown_on_exit=False)` +
  `BatchSpanProcessor(OTLPSpanExporter())`, then `trace.set_tracer_provider`.
- **Metrics**: `MeterProvider(resource=…, metric_readers=[PeriodicExportingMetricReader(OTLPMetricExporter(), …)], views=[…], shutdown_on_exit=False)`.
- **Logs**: `LoggerProvider(resource=…, shutdown_on_exit=False)` +
  `BatchLogRecordProcessor(OTLPLogExporter())`, and a
  `LoggingHandler(logger_provider=…)` on **the product's logger**, never the
  root logger (below). The handler copies the current span's `trace_id` and
  `span_id` onto every record, which satisfies §1.4.

The API's tracer and meter are proxies: `trace.get_tracer(__name__)` and
instruments created at import time bind to the providers installed later, and
stay no-ops when none are. So product modules may define their instruments at
module level.

Providers are global per process and can be set once. Tests that exercise real
export therefore run the product in a **subprocess**.

## Which variables the SDK reads, and which the module must

With providers built by hand, **the SDK still reads**:

- the exporters: `OTEL_EXPORTER_OTLP_[<SIGNAL>_]{ENDPOINT,HEADERS,TIMEOUT,COMPRESSION,CERTIFICATE,CLIENT_*}`
  (a base endpoint gets `/v1/<signal>` appended; a per-signal one is used as is);
- `Resource.create`: `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`;
- `TracerProvider` with no sampler given: `OTEL_TRACES_SAMPLER`, `OTEL_TRACES_SAMPLER_ARG`;
- the batch processors and reader: `OTEL_BSP_*`, `OTEL_BLRP_*`, `OTEL_METRIC_EXPORT_{INTERVAL,TIMEOUT}`;
- **`OTEL_SDK_DISABLED`**: all three providers honour it and hand out no-ops
  (a disabled tracer's spans have an all-zero trace id).

**The module must read and validate itself**:

- `OTEL_TRACES_EXPORTER`, `OTEL_METRICS_EXPORTER`, `OTEL_LOGS_EXPORTER` — only
  the auto-configuration reads them, so a hand-built setup ignores `none`
  unless the module honours it;
- the protocol (above);
- the endpoint whenever a signal exports: the exporters fall back to
  `http://localhost:4318`, which §2 forbids — a missing endpoint is a startup
  fault;
- the required resource attributes (`deployment.environment.name`);
- "no `OTEL_*` at all → off": the SDK has no such rule; with no variables a
  hand-built setup would export to localhost.

Set `service.version` from the build and the platform's path marker
(`telemetry_source=otlp` on this estate) **after** merging the environment's
attributes, so neither can be overridden; set `service.instance.id` before it,
so a deployment that states one wins.

## Logging: never on the root logger

Attach the `LoggingHandler` to the product's own logger (`logging.getLogger("<product>")`)
and set that logger's level. **On the root logger it deadlocks shutdown when
the collector is unreachable**: the OTLP exporters report their retries through
`logging` ("Transient error … retrying in …"), the handler captures those, and
`LoggerProvider.force_flush` waits on records it keeps producing. Reproduced:
the process did not exit within 120 s; with the handler on the product logger
the whole shutdown took ~3 s against a dead endpoint. Pin it with a test that
fails on `addHandler` to `logging.getLogger()` with no name.

stdout is not a log pipeline: a CLI may print a few plain lines for the human
reading a CI log, but the structured record is the OTLP logs. On this estate
Alloy also tails container stdout (`log_source=docker`), and it misses
containers that live only a second or two, so never rely on it.

## Metrics specifics

- **Histogram buckets**: the SDK's default boundaries (0, 5, 10, 25 … 10 000)
  are for milliseconds. Record durations in seconds (unit `s`, as semconv asks)
  and install a `View(instrument_type=Histogram, aggregation=ExplicitBucketHistogramAggregation(<seconds>))`.
- **Short-lived processes**: the periodic reader may never fire. Give it a long
  interval and let the exit flush be the export; temporality stays cumulative.
- **Build identity**: an observable gauge `<app>.build.info` with value 1 and
  `version`/`revision` attributes; it arrives as `<app>_build_info`.
- **Naming as stored** (checked in Prometheus): dots become underscores, a
  counter gains `_total`, unit `s` adds `_seconds`, `{things}` units add
  nothing; `service.name` → `job`, `service.instance.id` → `instance`, every
  other resource attribute only on `target_info`.
- Synchronous gauges exist in the API (`meter.create_gauge(...).set(v)`); use
  them for "value at start of a run" rather than an observable callback.

## Shutdown and failure

- Turn the providers' own `atexit` hooks off (`shutdown_on_exit=False`); the
  module owns shutdown.
- Call `shutdown()` once per provider — it flushes. `force_flush()` then
  `shutdown()` exports metrics twice.
- Each exporter retries with backoff inside its timeout (default 10 s). Against
  a refused connection each signal gives up in ~1 s; against a black hole
  (accepts, never answers) each request waits the full timeout. So run the
  three shutdowns in a **daemon thread joined with a fixed budget** (code-vitals
  uses 5 s): the process exits on time whatever the collector does, and only
  telemetry is lost. Say so on stderr when the budget runs out.
- Export failures are logged by the SDK under `opentelemetry.*`; leave them
  there (and never route them back into OTLP — see *Logging*).

## Instrumentation

- **Database calls**: `opentelemetry-instrumentation-psycopg` is a beta
  (`0.66b1`) and records statement text by default. A few hand-written client
  spans per query are simpler: `SpanKind.CLIENT`, `db.system.name=postgresql`,
  `db.operation.name`, `db.query.summary` = a name for the query — never SQL
  text or bound values (§6).
- **Subprocesses** (git, tools): one client span per call, named for the
  command, no arguments that carry paths or content.
- **Inbound context**: a job started by CI has none (Woodpecker passes no
  `traceparent`); each run is a new trace. A server adopts incoming context in
  its transport layer as usual.

## Tests

- A **fake OTLP receiver**: an in-process `http.server` on `127.0.0.1:0`
  decoding `opentelemetry.proto.collector.{trace,metrics,logs}.v1` `Export*ServiceRequest`
  from the request bodies (the HTTP exporter sends uncompressed protobuf by
  default). Assert on what it received: resource attributes on every signal,
  a log record's `trace_id`/`span_id` equal to its span's, metric names, and
  that every data point's attribute keys are in the product's allowed set.
- Run the product in a **subprocess** per case (providers are global): with the
  receiver; with no `OTEL_*`; with `OTEL_SDK_DISABLED=true` (nothing arrives);
  with a half-configured set (startup fails); with a **black-holed endpoint**
  (a listening socket that never accepts — the run still succeeds and exits
  within the budget).
- The import-boundary test and the root-logger test above.
