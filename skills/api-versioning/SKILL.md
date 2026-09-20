---
name: api-versioning
description: Version contract for a remote API whose clients deploy independently of the server - how client and server negotiate a protocol version, how the server must behave, how a server is structured to serve several versions at once, and what change forces a new version. Language- and transport-agnostic. Load before designing a remote API, changing an existing API's messages or behaviour, adding or retiring an API version, or writing a client's connect path.
---

# api-versioning

**Premise.** Clients that are deployed independently of the server are
expected to lag it. A server upgrade must therefore never break a separately
deployed client, and mixed-version operation is the normal state rather than a
migration phase. The contract below is what makes "upgrade the server alone"
always safe. When the server and all of its clients are deployed together,
this skill is optional.

This is a design contract, not a library. It is stated in no language's or
transport's terms; apply it with whatever the repo uses. Where a repo's own
`AGENTS.md` or README records a deliberate deviation, that record wins.

**Terms**

- **Protocol version** — one generation of the wire contract (`v1`, `v2`, …).
  It is *not* the server's release number: many releases serve the same
  protocol version, and one release serves several. Versions are always listed
  in **preference order, most preferred first** — the server's list in the
  handshake and a client's own enumeration alike.
- **Discrimination** — a request must be able to state which single version it
  is.
- **Route** — the address of one operation, and the preferred mechanism to
  discriminate versions. **Each protocol version owns its own routes** (gRPC:
  the protobuf package embedded in the path; HTTP: a path prefix), so two
  versions serve concurrently on one server with no dispatch ambiguity.
- **Handshake** — the operation that reports every version the server
  supports. It is the only operation that is not versioned and not routed by
  version (§1).
- **Version-not-served error** — one stable, distinct error kind, never the
  transport's generic not-found, so a retired version never looks like a
  mistyped route. It names the version that was asked for. Its client-side
  counterpart is the **incompatible-version error**, raised when client and
  server have no version in common; it names both lists.

## 1. The version negotiation contract

1. The client opens a connection that can do nothing but negotiate. The
   handshake is the first operation a client calls on a logical connection,
   and the only one that can be called before a version is negotiated. It is
   not versioned and not routed by version.
2. The client sends the list of versions it supports. It exists for the
   server's usage records only — what clients in the field can speak. The
   server must not filter or reorder its response by it, and treats it as
   untrusted input.
3. The server answers with **every version it serves, most preferred first** —
   whatever the client listed — and **never rejects** the request. Each version
   in the response may carry a deprecation date (RFC 3339, UTC). It states the
   server's intent: the version is not expected to be retired before that date
   — an emergency such as a security flaw excepted — and may be served longer.
   It is not a guarantee.
4. The client should select the most preferred version in the server's list
   that it supports — passing over a version that carries a deprecation date
   when it also supports one that does not — but is not required to: it may
   select any version that it supports and the server serves. It must not
   proceed with a version that is not in the list. A client that selects a
   version carrying a deprecation date surfaces a warning to its operator and
   never fails because of it. If client and server have no version in common,
   the client aborts with the incompatible-version error.
5. **Every operation that follows travels on the negotiated version's routes.**
   What an operator is shown as "the session's version" is read back off that
   transport, so a reported version and a dialled route cannot disagree.
6. **If a call fails with the version-not-served error, the client repeats the
   handshake once**, selects again, and retries that call on the newly selected
   version — the rejected call never executed, so the retry is safe. It logs
   the change of version. If no version is in common, or the retry fails the
   same way, it aborts.

**The handshake's shape is fixed, forever.** It can never be versioned, so it
never changes: the request carries the client's version list; the response is
the list of versions, each with an optional deprecation date. It never gains,
loses or repurposes a member. Anything else a client needs belongs in a
versioned operation.

## 2. How the server must behave

**The rule that makes this work: adding a protocol version must never change
what an existing version's clients see.**

- **Serve versions concurrently.** The server must be able to serve multiple
  versions at once, and must not reject a request for a version it serves.
- **An unserved version gets the version-not-served error** — whether the
  version was retired or never existed.
- **Decide and record whether the handshake needs credentials.**
  Unauthenticated lets the authentication scheme vary by version, but exposes
  the version list to anyone and makes the client's list anonymous input;
  authenticated hides the list, but freezes the authentication scheme across
  every version. The repo records which it chose and why.
- **Behaviour is contract.** What an operation *does* is part of its version,
  not just its signature (§3).

## 3. What forces a new version

A new version is required when the shape of any API or substantive operation
changes. Even new optional fields or new operations can break clients.

A new version **is** required for:

- renaming, renumbering, retyping, removing or repurposing an existing field;
- changing what an existing operation does;
- adding any operation or field, even if those are optional;
- changing the set of values an existing field may carry — a wider or narrower
  grammar, letter case, range, or a new enumeration member. Clients validate
  what they were built to expect, and one unexpected value can fail a whole
  response.

A new version is **not** required for bug fixes or performance improvements
that do not change the shape of any API or substantive operation.

**Exceptions are approved before implementation and recorded** — with the
reason and who they can affect. A rule with an unrecorded exception reads as a
rule that is negotiable.

**Retrofitting the handshake** onto an API that lacks one needs no exception:
the handshake is unversioned, so adding it changes no existing version, and
deployed clients never call it. A client that finds no handshake on a server
treats it as serving exactly the one legacy version.

## 4. How the server implements it

One implementation, however many versions:

```
handshake ─────────────────────► served-versions list  (unversioned, no shim)

wire vN ─┐
wire vM ─┴─ per-version shim ──► shared implementation ──► store
            (adapter: translate,  (version-free: authz, business
             mutate, basic         validation, control flow)
             validation)

any other version-shaped route ► version-not-served error  (catch-all)
```

- **Version-free core.** Domain types and the shared implementation are
  written in no protocol version's terms.
- **A shim per version per service, acting as an adapter** between that
  version's wire contract and the shared implementation, each constructed over
  the *same instance* of the shared implementation. A shim is free to mutate
  or translate a request or response in any way that version requires.
  Business logic stays in the shared implementation: logic duplicated across
  shims belongs there.
- **Shims share, they do not chain.** Because every added field or operation
  is a new version (§3), most of a new version is unchanged. Adapter code for
  an operation whose wire shape is identical in several versions lives once
  and is referenced by each of those shims. A shim never calls another
  version's shim, so any version can be retired without touching the rest.
- **The shim does basic validation** — what that version's wire contract
  itself demands. If a field is marked mandatory for a given version, a
  request that omits it is rejected by the shim with a validation error. **The
  shared implementation validates the business logic** of the request and
  response, and returns the appropriate error when either is invalid.
- **The shared implementation never branches on the version.** The call
  context may record which version a call arrived on (for metrics); behaviour
  that differs per version is a forked server with extra steps.
- **Wire types stop at the shim** — except a type the shim deliberately passes
  through (below). Enforce it mechanically: a lint or test that fails when
  anything else imports wire/generated types, with the passed-through types as
  its explicit allowlist.
- **A shim may pass a wire type through untranslated** when that type is
  identical in every served version and expected to stay so; the decision is
  the shim's. The cost is deferred, not avoided: when a later version must
  change that type, the refactor adds a core type, a shim translation for each
  version, and updates the shared implementation to use the core type.
- **The handshake sits outside the shims.** It is unversioned, so it has no
  per-version form; it reports the served versions and nothing else.
- **A catch-all covers every version-shaped route the server does not serve**
  and returns the version-not-served error. Retiring a version is then just
  removing its routes: they fall to the catch-all.

**The client mirrors it.** A connection type that can only negotiate; a
transport bound to one negotiated version, obtainable only by naming that
version; one dialer module per version, in the same adapter role and sharing
adapter code the same way. A re-handshake (§1.6) obtains a new transport; it
never rebinds an existing one. Select the dialer with an **exhaustive match
over the version enumeration**, so declaring a version that has no dialer
fails to build (where the language cannot check exhaustiveness, a test that
iterates every declared version). **Never fall back to an older version's
dialer**: the session would report one version while its traffic travels on
another's routes (§1.5).

**Tests that protect the contract — do not weaken them:**

- a server newer than this client build still connects;
- the handshake reports every version the server serves, most preferred
  first, and the response is the same whatever list the client sends;
- a client that shares no version with the server aborts with the
  incompatible-version error;
- a request for a version the server does not serve — retired or never served
  — gets the version-not-served error, not the transport's not-found;
- a client whose version is retired mid-session re-handshakes once, retries on
  the newly selected version, and aborts if that fails too;
- a client that selects a version carrying a deprecation date warns and still
  works;
- for **every** declared version, each operation reaches a route naming that
  version, asserted on what the server *received*. Iterate the enumeration so
  there is no list to extend;
- a test-only extra version registered beside the real one in the server's own
  tests, proving concurrent serving before it is relied on.

## 5. Version lifecycle

Version expiry should be planned, but is not required to be. A service should
not create a versioned API without understanding the conditions in which a
particular version is no longer needed, should have a plan for retiring
versions, and should communicate that plan to clients — considering the impact
on them and giving a reasonable notice period. None of that binds the server:
a version in which a security flaw is discovered, for example, is likely to be
dropped immediately.

It is recommended, but not required, that the service records usage of
versions — both the version each request names and the lists clients send in
the handshake.

It is not acceptable to keep a version alive indefinitely, as this leads to
technical debt and increased maintenance cost. Any version can be retired once
it is no longer needed, and versions do not need to be retired in any
particular order.

See `references/lifecycle.md` before adding or retiring a version.
