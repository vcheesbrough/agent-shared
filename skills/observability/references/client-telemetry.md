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

## One endpoint per environment

**Every environment has exactly one ingest endpoint, shared by every service in
it.** Production and dev are separate deployments of it, on separate hostnames,
with separate configuration. One implementation to write, one to operate, one
place where quotas and caps live.

**The environment stays structural.** `deployment.environment` is stamped by
the deployment that answered, from its own config, and no request can change
it: a dev client cannot land in production, because production is a different
deployment at a different address. That is the boundary this design keeps, and
it is the one that matters most — dev data in production dashboards is the
failure that wastes an incident.

**`service.name` comes from the client, and is trusted.** No mapping to
maintain, no registration to resolve: the client states which product it is and
the endpoint takes it. One guard remains, and it is not about honesty — the
value must match a known set of service names, because `service.name` becomes a
stream label downstream and an arbitrary string from a client is a cardinality
problem whether or not anyone is lying.

### What the endpoint can actually prove

Two tiers, and the difference matters the moment a number on a dashboard is
challenged.

- **Structural — the caller cannot choose it.** The environment, stamped by the
  deployment that answered; and the user, from claims the provider signed.
- **Asserted — the client says so.** The service, the client kind, the build
  version, the platform, the device class. Taken at face value, bounded where
  they become labels.

**Then ask what a lie would buy.** A client claiming another product's name
pollutes that product's dashboards, spending its own authenticated user's
quota, inside one environment. It cannot reach another environment, another
user's data, or anything the product itself protects. That containment is what
one endpoint per environment still buys; everything finer is a data-quality
measure, not a security one, and should be argued for on those terms.

### What the shared endpoint has to carry

One property came free when each service owned its ingest, and now has to be
built:

- **Quota, rate limit and kill switch, per user and per service.** Previously a
  service's ingest could be capped or turned off by its own deployment; now
  they are configuration in the shared service. Keyed on a claimed
  `service.name` these serve the honest case — a runaway client build, which is
  what they are for — while the per-user quota is the one that holds
  regardless.

**Configuration and ingest can now disagree.** The app tells its clients where
to send and whether to send; the shared endpoint decides whether it accepts.
When those disagree, clients send to a door that answers `403`, which they
handle correctly and which moves the rejection counter — so the disagreement is
visible rather than silent.

**Same-origin is what is given up**, and the browser pays for it: the session
cookie no longer applies to a different host, so the browser needs an access
token in JavaScript, with CORS preflight on every export and ad-blocker
exposure on a non-first-party hostname. If that trade turns out badly, the
cheapest repair is a thin same-origin route on each app that authenticates with
the cookie and forwards to the shared endpoint — a few lines per product, and
it restores cookie auth and same-origin without giving up the single ingest
deployment.

The shared endpoint carries the five capabilities of *The invariant*; a
collector with an auth extension is not one of them unless the missing four are
supplied in front of it, and per-user quota is the one to check first.

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
- **A session cookie representing an OIDC session** — available only where
  ingest is same-origin with the app, so under the shared endpoint it applies
  only behind a thin per-app forwarding route. Acceptable because the session
  was established by OIDC login and that route re-checks it exactly as every
  other authenticated route does — including the same telemetry permission, not
  merely "is logged in" (below). It keeps the access token out of JavaScript,
  which is why it remains the better browser option where it is available.

**Validate audience, not just signature.** A token the provider minted for a
different client is a valid token; accepting it makes the ingest endpoint a
confused deputy for every application in the estate.

### The telemetry permission

Require a dedicated scope — `telemetry:write` — and check it. Be clear about
what it buys, because the obvious reason is the wrong one.

**It is not what keeps other applications out.** The audience check does that,
with or without a scope. A scope that every user of the application always
holds is a constant, and a check against a constant is ceremony.

**It earns its place when it can be absent.** A separate permission is what
lets ingest be withdrawn from one user or group without touching their access
to the product — a privacy opt-out enforced by the provider instead of by
trusting the client to stop sending, or a way to cut off one abusive account
without a deploy. Confirm your provider can actually withhold a scope per user
or group before designing on it: many grant scopes per client registration, and
such a scope only tells you which client asked, which the audience already
said.

**Both authentication forms answer the same question.** The decision is *may
this identity write telemetry for this service* — read from the token's scope
on the bearer path, and from the session's entitlement on the cookie path,
where there is no token to carry a scope. Those two must consult the same rule.
If they do not, the browser and the mobile client are governed by different
policies, and that surfaces during an incident.

**Name the capability, not the protocol.** `telemetry:write`, not
`otlp:write` — the permission should survive a change of wire format, and the
day a second ingest path exists, one permission should not have two names.

**Refusal is loud at the endpoint and quiet at the client.** Answer `403`,
distinct from an authentication failure, and count it: a client build that
forgets to request the scope otherwise loses telemetry in silence, and nobody
finds out until they need a trace. The client treats it as permanent and stops,
like any other non-retryable answer.

### What you validate, and what you rely on

**Token claims are the identity provider's statements, not the client's.** The
client chooses which token to present; it does not choose what is inside one.
So the checks are a closed list — signature against the issuer's JWKS, issuer,
audience, expiry, scope — and once those pass, the claims are *relied on*.
Do not attempt to police the values of `sub`, `azp` or anything else: there is
nothing to check them against, and an endpoint that re-derives what the
provider has already asserted is doing the provider's job, worse.

The residual risk is not a lying claim. It is an issuance question — which
clients the provider will mint tokens for, under which flows, with what
lifetime — and it is settled in the provider's configuration, not at the ingest
endpoint.

Three kinds of input arrive, and they are treated differently:

| Source | Treatment |
| --- | --- |
| Signed by the provider — identity, audience, scope | Validated once against the closed list, then relied on |
| Chosen by the caller — the route, and which token to send | Bounded by routing and the audience check; what remains is data quality, not security |
| The request body — everything OTLP carries | Trusted as sent, apart from the short list in *What the endpoint changes about the payload* |

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

## What the endpoint changes about the payload

**Everything the client sends is trusted as sent, except what this section
lists.** A field or attribute not named here is the client's to state and the
endpoint's to pass through unread: there is no allowlist to curate, no schema
to keep in step with three client builds, and nothing further to decide. Values
are believed; the limits below are about volume, not honesty, and apply to
everything.

The complete set of exceptions:

- **Stamped by the endpoint, whatever the client sent.**
  `deployment.environment` from the receiving deployment's own config, and the
  user and session identity from the authenticated context (named below). What
  the client claimed is discarded, not merged.
- **`service.name` is bounded**, not overwritten: taken from the client, and
  required to match a known set of service names — a cardinality guard,
  because it becomes a stream label downstream.
- **`service.version` is the client's build, not the receiver's.** Do not stamp
  the receiving deployment's version onto a span that came from somewhere else;
  if the receiver's own version is useful, it goes in an attribute of its own.
- **Client-origin spans are marked** (`telemetry.source=client`). Trace ids are
  chosen by the client, and a user trivially knows their own, so spans can be
  injected into a trace the server also writes to. Guessing a stranger's
  128-bit id is impractical; injecting into a known one is not. The marker is
  what lets a reader tell which spans the server vouches for.
- **Timestamps are clamped.** Device clocks are wrong, and mobile clients flush
  offline buffers hours later. Reject far-future outright, and set a far-past
  policy that matches the backends' ingestion windows — otherwise the store
  silently drops exactly the offline data the buffering was built for.
- **Attribute count and value length are capped**, and what exceeds them is
  dropped. A volume control, applied without reading anything.

Two consequences of trusting the rest, worth stating once:

- **Nothing that must be true may depend on a client-stated value** — routing,
  tenancy, retention, quota, access. Trusting a value for telemetry is not
  trusting it for decisions.
- **Client values never become metric labels** (`../SKILL.md` §4). That is a
  cardinality rule, not a trust one, and it survives everything above.

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

## Which attributes carry identity

Identity on client telemetry is carried in the **`user.*`** namespace, stamped
by the ingest endpoint from the authenticated context. Every attribute here is
still marked *Development* in OpenTelemetry's registry, so expect the names to
move and keep them behind whatever the telemetry module already centralises.

| Attribute | Source claim | |
| --- | --- | --- |
| `user.id` | `sub` | **Mandatory** |
| `user.name` | `preferred_username` | **Mandatory** |
| `user.email` | `email` | Stamped when present |
| `user.full_name` | `name` | Stamped when present |

**This is attribution over minimisation, chosen deliberately.** Telemetry that
names its user answers "what happened to *this* person" directly, without a
lookup and without a pseudonym table to maintain. The price is in *What follows*
below, and that price is not optional.

**Mandatory means the request fails.** A valid token lacking `sub` or
`preferred_username` is a provider misconfiguration, and the alternative to
refusing it is telemetry that cannot be attributed to anyone. The whole OTLP
request is refused — not a filtered part of it — and three things happen:

- **The client is told.** `403`, so the client treats it as permanent and stops
  for the session instead of retrying a batch that can never succeed (*What the
  client must do*). The response names the missing claim and nothing else: this
  is a configuration fault, and naming it is the difference between a
  five-minute fix and an afternoon.

  **`403`, not `400` or `401`.** `400` is what a malformed payload returns, and
  sharing a code would make "your protobuf is wrong" indistinguishable from
  "your token is incomplete" — different fix, different system, different
  owner. `401` invites the client to refresh and retry, which against a
  provider that is not emitting the claim yields an identical token and loops.
  It is also the mapping RFC 6750 gives: `invalid_request` → 400,
  `invalid_token` → 401, `insufficient_scope` → 403, and a valid token that
  does not carry enough to proceed is the third. The missing
  `telemetry:write` permission answers the same way, so both
  "authenticated but not enough" refusals behave identically and differ only
  in the reason recorded against the counter.
- **The server warns.** A warning, not an error — nothing is broken for the
  user and nobody should be woken — carrying the missing claim, the route, and
  the token's client id, which is what identifies the misconfigured
  registration. Never the token itself. Rate-limit it: when a provider stops
  emitting a claim, every request from every client produces one.
- **The counter moves.** Rejections are counted by reason, and that counter is
  what a dashboard or an alert watches. A log line explains one instance; the
  counter is what shows it is happening at all, which is the part nobody
  notices otherwise.

None of this reaches the product's own users: a telemetry request is refused
and the application carries on.

It also means the provider must emit `preferred_username` on the access token
for **every** client that sends telemetry. A scope-mapping change there stops
ingest here — worth knowing before someone tidies the provider's scopes.

**The optional two are taken when the token already carries them**, and their
absence is never an error. Do not widen a token's scopes to obtain them: they
are a convenience, and a token minted wider for telemetry's sake makes every
service that receives it a holder of more personal data.

Not stamped:

- **`user.roles`** — a snapshot that ages badly, and in a small tenant a role
  names a person. Role questions are answered from the product's own data.
- **`user.hash` and `enduser.pseudo.id`** — a pseudonym beside a stamped
  `user.id` and `user.name` is decorative. The data is identity-bearing by
  design; pretending otherwise is worse than not pretending.

Stamped alongside them:

- **`session.id`**, with `session.previous_id` — the client session that a
  group of spans, logs and events belongs to. It is what most client-side
  investigations actually group by, and unlike the identity attributes it is
  meaningful without naming anyone.

**One helper, used everywhere.** The ingest endpoint and the product's own
server-side request spans stamp the same attributes from the same claims.
Otherwise one person is two identities, and a client span cannot be joined to
the server work it caused — which was the point of collecting it.

**The client sets none of them.** The endpoint stamps from the authenticated
context and discards whatever arrived.

### What follows from stamping identity

Three things are now true that were not, and they are obligations rather than
observations:

- **Access to traces and logs is access to identities.** Grafana, Tempo and
  Loki permissions are a personal-data control now, not only an operational
  one, and they are reviewed as such.
- **Retention is the main mitigation.** A short window is doing real work here:
  it bounds how long the store holds names. Treat it as a control that is
  stated and defended, not a storage setting someone may tune upward for
  convenience.
- **Deletion has to be answerable.** When a user asks to be deleted, the
  telemetry store is one of the places holding them. Either deletion reaches it
  or retention answers within a window you are prepared to state out loud.
  Decide which, before someone asks.

And one that was already true and now matters more: **these values never become
metric labels** (`../SKILL.md` §4). They are exactly the unbounded kind.

## Privacy and retention

Beyond the identity attributes above, a user's device sends plenty that is
personal without being meant as identity: IP addresses, user agents, full URLs
with query strings, and screen or route names that may identify content.
Redact at the ingest endpoint, before it reaches a store with different access
control from the product's database, and set a retention period deliberately
rather than inheriting the platform's. Stamping identity is a decision that was
made; carrying content alongside it is usually an accident.

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
