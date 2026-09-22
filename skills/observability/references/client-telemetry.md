# Client telemetry: OTLP from browsers and mobile apps

Companion to `../SKILL.md` §2. Read it before accepting telemetry from anything
running on a user's device — a browser SPA, a mobile app, a desktop client.

Server telemetry comes from a process you deployed. Client telemetry comes from
a device you do not control, sent by a build you cannot recall, across a
network you do not own, by a user who may be adversarial. Every rule here
follows from that one difference.

## The invariant

**A collector's OTLP receiver never faces the internet** — not even one that
validates OIDC. A collector has no per-user quota, no request-level rate limit
and no notion of an abusive caller, and its failure mode under load is
memory-shaped.

What faces the internet is an **ingest endpoint you own**, which authenticates,
bounds, sanitises and re-emits into a collector that stays unreachable. The
collector behind it is protected exactly as any other sidecar: loopback or a
private network, no published ports, no Docker socket, config the app cannot
rewrite, memory-limited, and never in a health gate (`../SKILL.md` §6).

This holds whether the client is on the local network or on the public
internet. Nothing below replaces it.

## Two topologies

**Same-origin, through the app** — the default. The ingest route lives on the
product's own hostname, so the browser authenticates with the session cookie it
already has, there is no CORS preflight, no access token in JavaScript, and
first-party paths largely escape ad-blocker filter lists. One public surface,
one auth implementation, and the endpoint can stamp trusted attributes because
it already knows the user.

**A dedicated ingest service** on its own hostname — when telemetry volume
would threaten the product's own capacity, or when several products share one
ingest. It costs CORS, a token in the browser, ad-blocker exposure and a second
auth implementation, so take it for the volume argument, not for tidiness.

## Authentication

The client holds a *user* token, so OIDC fits here in a way it does not for
server-side export (which has no user and needs a machine identity). Require a
narrow scope — `telemetry:write` — and let the client's existing OIDC stack
handle refresh. Browsers use the session cookie; mobile clients send the bearer
token they already hold.

**Decide the pre-authentication case deliberately.** Crashes during startup,
failed logins and broken OIDC redirects are among the most valuable traces a
product can collect, and in every one of them the user has no token. Either:

- **drop it**, accepting blindness exactly where authentication is broken; or
- **accept it on a separate anonymous path** with its own `service.name`
  (`<app>-spa-anon`), per-IP rate limits, aggressive sampling and shorter
  retention, never merged with authenticated data.

The second is usually right, and it is a distinct attackable surface that gets
built as one. What is not acceptable is discovering the question in production.

## Edge controls

All of these are mandatory on a public path.

- **Cap the decompressed body, not just the wire body.** OTLP/HTTP accepts
  gzip, and a 1 MiB upload expands to far more. Cap both; reject with 413.
- **Rate limit per identity and per IP**, the anonymous path harder. A quota in
  the endpoint, and a limit at the edge proxy in front of it.
- **Accept only what you use:** `POST`, the traces and logs paths,
  `application/x-protobuf`. Everything else is rejected, not tolerated.
- **Refuse OTLP metrics from clients.** Arbitrary metric names and labels
  arriving from the internet is unbounded cardinality with a stranger's hand on
  the dial — the one item here that can cost real money within an afternoon.
  Take traces and logs; derive metrics from spans server-side.
- **Timeouts**, and no keeping slow uploads alive.

## Treat the payload as hostile

- **Overwrite, do not trust.** `service.name`, `deployment.environment` and the
  user or session identity are stamped server-side from the authenticated
  context. Whatever the client claimed is discarded.
- **Bound attribute count and value length**; drop what exceeds them.
- **Mark client-origin spans** (`telemetry.source=client`). Trace ids are
  chosen by the client, and a user trivially knows their own, so spans can be
  injected into a trace the server also writes to. Guessing a stranger's
  128-bit id is impractical; injecting into a known one is not. The marker is
  what lets a reader tell which spans the server vouches for.
- **Clamp timestamps.** Device clocks are wrong, and mobile clients flush
  offline buffers hours later. Reject far-future outright, and set a far-past
  policy that matches the backends' ingestion windows — otherwise the store
  silently drops exactly the offline data the buffering was built for.
- **Keep client attributes out of metric labels**, always (`../SKILL.md` §4). A
  label fed from client input is an unbounded label by definition.

## Operating it

- **Public ingest lets someone else spend your storage and egress.** Set a
  per-user quota and a global ingest budget, and alert on ingest volume itself,
  not only on product metrics.
- **A kill switch that disables client ingest by config, without a deploy.**
  The first time a client build ships a telemetry loop, this is the only thing
  that stops it.
- **Client ingest is off until an environment enables it**, so a new
  environment never starts accepting volume nobody has looked at.
- **Never in the deploy health gate.** An ingest failure must not fail a
  product deploy.

## Privacy and retention

Telemetry from a user's device is personal data in a way server telemetry is
not: IP addresses, user agents, full URLs with query strings, and screen or
route names that may identify content. Redact at the ingest endpoint, before it
reaches a store with different access control from the product's database, and
set a retention period deliberately rather than inheriting the platform's.

## Making it worth the trouble

**Trace continuity is the payoff.** The point of client spans is that a user's
action and the server work it caused are one trace. The client must propagate
`traceparent` on its API calls, which for a browser also means the API's CORS
policy allows the header and the web SDK is configured to propagate to those
origins. Miss this and you have two disconnected traces and most of the value
is gone.

**Late data is normal.** Mobile clients buffer offline and flush on
reconnection, so plan for spans arriving hours after they happened, and check
that against the ingestion windows above before relying on it.
