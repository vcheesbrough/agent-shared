# Client telemetry: OTLP from browsers and mobile apps

Companion to `../SKILL.md` §2. Read it before accepting telemetry from anything
running on a user's device — a browser SPA, a mobile app, a desktop client.

Server telemetry comes from a process you deployed. Client telemetry comes from
a device you do not control, sent by a build you cannot recall, across a
network you do not own, by a user who may be adversarial. Every rule here
follows from that one difference.

## The invariant

Client telemetry terminates against something that can do five things:

1. **authenticate the user against the product's OIDC provider**,
2. **enforce a per-user quota**,
3. **rate-limit the caller**,
4. **cap the decompressed body**, and
5. **overwrite what the payload claims about identity**.

Only then is it re-emitted into a collector. This holds whether the client sits
on the local network or on the public internet, and it is a requirement about
capabilities, not about which binary is listening — the ingest endpoint is an
OTLP receiver facing users either way.

**A collector binary supplies none of the five.** Alloy and the OpenTelemetry
Collector have no notion of a user, no quota, no request-level limit, and their
failure mode under abuse is memory-shaped. So a collector never terminates a
client connection on its own: it sits behind something that does.

A collector *fronted* by layers that supply the rest — edge rate limits and
body caps at the proxy, processors that overwrite resource attributes — can be
made to satisfy this, and hosted OTLP endpoints are exactly that. Two things to
weigh before choosing it over an endpoint you wrote: **per-user quota is the
capability with no off-the-shelf answer**, and it is the one that decides your
storage bill; and authentication is the capability a collector most easily
gains, while being the one that helps least on its own — an authenticated
caller can still exhaust the budget, and a valid token says nothing about
whether the `service.name` in the payload is honest.

The collector behind the ingest endpoint is protected as any other sidecar:
loopback or a private network, no published ports, no Docker socket, config the
app cannot rewrite, memory-limited, and never in a health gate
(`../SKILL.md` §6).

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
auth implementation, so take it for the volume argument, not for tidiness. It
carries the same five capabilities as the app would; a collector with an auth
extension is not one of these unless the missing four are supplied in front of
it, and per-user quota is the one to check first.

## Authentication

**Client telemetry is authenticated by OIDC.** The client holds a *user*
identity, so OIDC fits here in a way it does not for server-side export (which
has no user and needs a machine identity). The identity on a telemetry request
is the one the product's identity provider issued — never an API key, never a
shared ingest secret, never a client-generated device or installation id.
Anything else is a second identity system, and it would be the weakest one the
product has.

Two forms are acceptable:

- **A bearer access token from the identity provider.** The canonical form, and
  the only one available to a native client or to a dedicated ingest service on
  a different origin. The endpoint validates it as it would any other API call:
  signature against the issuer's JWKS, issuer, **audience**, expiry, and a
  narrow scope such as `telemetry:write`.
- **A session cookie representing an OIDC session**, for same-origin ingest on
  the product's own hostname. Acceptable because the session was established by
  OIDC login and the ingest route re-checks it exactly as every other
  authenticated route does — including the scope or entitlement, not merely
  "is logged in". It keeps the access token out of JavaScript, which is why
  it's the better browser option.

**Validate audience, not just signature.** A token the provider minted for a
different client is a valid token; accepting it makes the ingest endpoint a
confused deputy for every application in the estate.

**Tokens expire, and the exporter must notice.** Let the client's existing OIDC
stack refresh, and make sure the OTLP exporter reads the current token **per
request** rather than binding a header once at initialisation — several SDKs
do the latter by default. The failure is silent: an expired token gives a
non-retryable 4xx, the batch is dropped, and the signal that would have told
you is the one that just stopped.

**Decide the pre-authentication case deliberately.** Crashes during startup,
failed logins and broken OIDC redirects are among the most valuable traces a
product can collect, and in every one of them the user has no token. Either:

- **drop it**, accepting blindness exactly where authentication is broken; or
- **accept it on a separate anonymous path** with its own `service.name`
  (`<app>-spa-anon`), per-IP rate limits, aggressive sampling and shorter
  retention, never merged with authenticated data.

The second is usually right, and it is a distinct attackable surface that gets
built as one. What is not acceptable is discovering the question in production.

**An anonymous path is not a second authentication scheme.** It carries no
identity at all, it is labelled as unidentified, and nothing downstream —
dashboard, alert or investigation — may treat what arrives on it as attributed
to anyone. The moment it grows a device id or an ingest key to "tell clients
apart", it has become the second identity system this section forbids.

## What the client must do

**Failing to reach the ingest endpoint is a normal condition, not an
exceptional one.** Phones lose signal, browsers close mid-flush, captive
portals intercept, blockers cancel the request, and ingest gets turned off
between one launch and the next. The client treats all of it the same way:
**drop the events and carry on.** Telemetry loss is never an error the user
sees, never a crash, never a blocked interaction, and never a reason to try
harder.

- **Bounded buffer, oldest dropped first.** Cap it by count and by bytes. A
  buffer that grows until the export succeeds is a memory leak on a device you
  do not control and cannot debug.
- **Retry within the session, never beyond it.** A batch may be retried later
  in the same session, with exponential backoff and jitter and a cap on
  attempts, after which it is dropped. Nothing is persisted to be re-sent on a
  later launch — stale telemetry is worth less than the storage and the
  ingestion-window trouble it causes.
- **Retry only what is retryable.** `429` and `5xx` are worth backing off and
  retrying, honouring `Retry-After`. `400`, `401`, `403` and `413` are
  permanent answers for that payload: drop it. On `401`, stop exporting until
  the token has been refreshed rather than looping on a token the endpoint has
  already rejected.
- **Never on the critical path.** Export happens off the UI thread and outside
  any interaction. The application behaves identically whether telemetry is
  working, failing, or switched off entirely.
- **Assume you are a crowd.** When ingest fails, it usually fails for every
  client at once, and they all retry together. Backoff with jitter, and give
  up for the rest of the session after repeated failure — a client fleet
  retrying in lockstep is a self-inflicted denial of service against the
  product it is meant to be reporting on.
- **Flush on the way out, best effort.** A page-hide beacon, a bounded flush
  when a mobile app backgrounds — never delaying exit, never blocking the
  close.

## Telemetry configuration comes from the product

**The client has no default endpoint.** It receives its telemetry
configuration from the product — whether ingest is enabled, where it goes, how
much to sample — and **in the absence of that configuration it does not
initialise OTLP at all.** No compiled-in fallback, no endpoint derived from the
app's own origin, no localhost, no attempt to find out by trying.

This is the client-side form of §2's rule for servers (one endpoint,
configured, never compiled in) and of §5's rule that disabled is explicit: on a
client, **absent configuration is disabled**, unambiguously.

It is also what makes the kill switch real. Turning client ingest off has to
reach clients that are already installed and that you cannot recall; if the
endpoint is baked into the build, a released client keeps sending to a path you
have disabled, and the only remedy is an app-store release.

Three consequences to design for:

- **Configuration arrives after startup.** Spans from the launch sequence — the
  ones you most want — either wait in a small, bounded, short-lived buffer or
  are discarded. If configuration never arrives, they are discarded. Never hold
  them for the whole session in hope.
- **A failed configuration fetch is absence, not an error.** No telemetry, no
  aggressive retry, no message to the user.
- **Configuration changes between launches**, in both directions. The client
  honours the newest it has been given, including "off".

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
