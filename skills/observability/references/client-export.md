# Client telemetry: what a client must do

Companion to `../SKILL.md` §6. Read it before writing the telemetry side of
anything that runs on a user's device — a browser SPA, a mobile app, a desktop
client. The receiving side — the ingest endpoint, its authentication, and what
it changes about the payload — is `client-ingest.md`; read that instead when
building or operating the endpoint.

Server telemetry comes from a process you deployed. Client telemetry comes from
a device you do not control, sent by a build you cannot recall, across a
network you do not own. Every rule here follows from that: the client is a
guest of an endpoint that may refuse it, throttle it or not be there at all,
and it behaves well in every one of those cases.

## Presenting a credential

**Every request carries the user's identity from the product's OIDC
provider** — never an API key, never a shared ingest secret, never a
client-generated device or installation id (`client-ingest.md`,
*Authentication*). Two forms exist:

- **A bearer access token from the identity provider.** The canonical form,
  and the only one available to a native client, which has no cookie. It
  carries the telemetry scope (`telemetry:write`) and the audience the ingest
  expects; the provider mints them and the app requests them.
- **A session cookie representing an OIDC session**, where the ingest is
  same-origin with the app and validates that session itself. It keeps the
  access token out of JavaScript.

**Tokens expire, and the exporter must notice.** Let the client's existing OIDC
stack refresh, and make sure the OTLP exporter reads the current token **per
request** rather than binding a header once at initialisation — several SDKs
do the latter by default. The failure is silent: an expired token gives a
non-retryable 4xx, the batch is dropped, and the signal that would have told
you is the one that just stopped.

**Every refusal of the token is `401`**, whatever the reason — missing,
invalid, expired, lacking the scope or a required claim — with the failed rule
named in the body (`client-ingest.md`, *Which attributes carry identity*). The
client's response is one refresh, then stop (*Failure is normal*).

**Pre-authentication telemetry is emitted locally instead.** Crashes during
startup, failed logins and broken OIDC redirects happen when there is no
identity to send under, and they are still worth recording — so the client
writes them through the platform's own mechanism, the JavaScript console or the
system log (*Failure is normal*), and sends nothing.

The cost, stated once and accepted: those events reach nobody unless someone
can read that device's logs. Failures before a user is authenticated are
visible in development and in a support conversation, not on a dashboard. That
is the price of having no unauthenticated public surface at all.

## Failure is normal

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
- **Retry only what is retryable.** OTLP names the retryable answers, and
  they are the only ones: `429`, `502`, `503` and `504`, backed off and
  retried honouring `Retry-After`. Every other `4xx` or `5xx` — `400`, `401`,
  `403`, `413`, and `500` too — is permanent for that payload: drop it.
  **`401` gets one refresh.**
  Every refusal of the token is `401`, so the code cannot tell an expired
  token from a misconfigured provider. Stop exporting until the token has been
  refreshed, then resume; if the next batch is refused too, stop for the
  session. A second `401` on a fresh token is not going to change, and
  retrying it is the loop this rule exists to prevent.
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
- **Say so locally.** A failed export is the one failure that cannot report
  itself: the channel that would have carried the news is the broken one. So
  the client writes to whatever local mechanism the platform has — the
  JavaScript console in a browser, the system log on Android or a desktop
  client — at warning level. Never a dialog, a toast, or anything else a user
  is made to read. Carry the status or error kind, the endpoint, and how many
  events were dropped; never the token, and nothing personal. A
  partial-success response that names rejected items is reported the same way.
- **Log transitions, not batches.** The first failure, the return to working,
  and the decision to give up for the session. A line per dropped batch floods
  the very tool someone would use to debug the page, which makes the diagnostic
  worse than silence. The same at startup: when no telemetry configuration
  arrived and OTLP was therefore never initialised, say so once — that line is
  the answer to "why are there no spans from this build".

## Telemetry configuration comes from the product

**The client has no default endpoint.** It receives its telemetry
configuration from the product — whether ingest is enabled, where it goes, how
much to sample — and **in the absence of that configuration it does not
initialise OTLP at all.** No compiled-in fallback, no endpoint derived from the
app's own origin, no localhost, no attempt to find out by trying.

This is the client-side form of §2's rule for servers (one endpoint,
configured, never compiled in) and of §5's rule that disabled is explicit: on a
client, **absent configuration is disabled**, unambiguously.

It is also what lets a deployment change its mind about clients it cannot
recall. Where the endpoint moves, or an environment stops offering ingest, a
configured client follows on its next launch; a client with the endpoint baked
into its build keeps hammering the old address until an app-store release
catches up with it.

Three consequences to design for:

- **Configuration arrives after startup.** Spans from the launch sequence — the
  ones you most want — either wait in a small, bounded, short-lived buffer or
  are discarded. If configuration never arrives, they are discarded. Never hold
  them for the whole session in hope.
- **A failed configuration fetch is absence, not an error.** No telemetry, no
  aggressive retry, no message to the user.
- **Configuration changes between launches**, in both directions. The client
  honours the newest it has been given, including "off".

## Encoding and transport

OTLP over HTTP, `POST` to the traces and logs paths — metrics are refused from
clients and derived from spans on the server side (`client-ingest.md`, *Edge
controls*). The ingest accepts both of OTLP's encodings, and the client sends
whichever is cheaper for it to produce: JSON is what a JavaScript SDK sends and
what a hand-rolled browser client builds from a serialiser it already has;
protobuf is smaller on the wire and needs only a message-encoding library.

## Making it worth the trouble

**Trace continuity is the payoff.** The point of client spans is that a user's
action and the server work it caused are one trace. The client must propagate
`traceparent` on its API calls, and the web SDK must be configured to propagate
to the origins it calls — same-origin `/api` needs no CORS allowance, but any
cross-origin call the app makes does. Miss this and you have two disconnected
traces and most of the value is gone.

**Late data is normal.** Mobile clients buffer offline and flush on
reconnection, so plan for spans arriving hours after they happened, and check
that against the ingest's timestamp policy (`client-ingest.md`, *What the
endpoint changes about the payload*) before relying on it.
