---
name: api-versioning
description: Version contract for a remote API whose clients deploy independently of the server - how client and server negotiate a protocol version, how the server must behave, how a server is structured to serve several versions at once, and what change forces a new version. Language- and transport-agnostic. Load before designing a remote API, changing an existing API's messages or behaviour, adding or retiring an API version, or writing a client's connect path.
---

# api-versioning

**Premise.** Clients that are not are deployed independently of the server are expected
to lag it. A server upgrade must therefore never break a separately deployed client, and
mixed-version operation is the normal state rather than a migration phase. The
contract below is what makes "upgrade the server alone" always safe.
It is entirely possible that the deployment of the server and all clients is coordinated, in which
case version negotiation is optional.

This is a design contract, not a library. It is stated in no language's or
transport's terms; apply it with whatever the repo uses. Where a repo's own
`AGENTS.md` or README records a deliberate deviation, that record wins.

**Terms**

- **Protocol version** — one generation of the wire contract (`v1`, `v2`, …).
  It is *not* the server's release number: many releases serve the same
  protocol version, and one release serves several. Order versions
  numerically, never as strings — `"v10"` sorts below `"v3"`.
  **Discrimination** a request must be able to describe which singular version it is.
- **Route/endpoint address is the preferred mechanism to discriminate versions** — the address of   
  one operation. **Each protocol version owns its
  own routes** (gRPC: the protobuf package embedded in the path; HTTP: a path
  prefix), so two versions serve concurrently on one server with no dispatch
  ambiguity.
  **Handshake** a handshake operation that reports all versions it supports, in order of preference, with most preferred being first. The client will send a list of the versions it supports, but this is indicative only, the server will respond with all versions it supports. The handshake is the only operation that is not routed by version, and it is the only operation that is not versioned. It is the first operation a client calls on a ;logical connection, and it is the only operation that can be called on a connection before a version is negotiated. Each version in the response may include a deprecation date (UTC), which is the date after which the server will no longer serve that version, it is indicative only and does not guarantee that the server will stop serving that version on that date. 

## 1. The version negotiation contract

1. The client opens a connection that can do nothing but negotiate. It sends
   the handshake to discover available versions. — the handshake is not routed by version.
2. The server answers with **every version it serves, most preferred first**, and
   **never rejects** the request.
3. The client is then free to select any of the versions reported by the server. If the client 
   cannot use any of the servers versions it should abort with a clear error indication. 
   It must not proceed with a version that is not in the list. If the server 
   receives a request for a version it does not serve it should return a clear error indication.
4. The client _should_ select the most preferred version that it can support
   but it is not required to do so. The client may select any version that it supports and that the server serves. If the client and server have no versions in common, the client should abort with a clear error indication. The handshake
5. **Every operation that follows travels on the negotiated version's routes.**
   What an operator is shown as "the session's version" is read back off that
   transport, so a reported version and a dialled route cannot disagree.
6. The server must server multiple versions concurrently, and must not reject a request for a 
   version it serves. The server may return a clear error indication if the client requests 
   a version that it does not serve.

## 2. How the server must behave

**The rule that makes this work: adding a protocol version must never change
what an existing version's clients see.** 

- **Behaviour is contract.** What an operation *does* is part of its version,
  not just its signature (§3).

## 3. What forces a new version

A new version is required when the shape of any api or substantive operation changes.
Even new optional fields or new operations can break clients.

A new version **is** required for:

- renaming, renumbering, retyping, removing or repurposing an existing field;
- changing what an existing operation does.
- Adding any operation or field even if those are optional.

Note that a new version is **not** required for for bug fixes or performance improvements that do not change the shape of any api or substantive operation.

**Exceptions are approved before implementation and recorded** — with the
reason and who they can affect. A rule with an unrecorded exception reads as a
rule that is negotiable. The one legitimate exception is the bootstrap:
retrofitting this handshake onto an API that lacks it may have to change the
handshake in place, because shipping it as a new version would reproduce the
flag day it exists to remove. When retrofitting, clients treat an absent
served-set as "this server serves exactly the version it echoed".

## 4. How the server implements it

One implementation, however many versions:

```
wire vN ─┐
wire vM ─┼─ per-version shim ──► shared implementation ──► store
         │  (translate only)     (version-free: authz, validation,
         │                        control flow, every error status)
handshake: per-version by nature (the echo)
```
- The per-version shim may choose to not translate the wire type if it is identical
  to all future types, but it is the shim's responsiblity to make this decision.
  It is noted that if it discovered in the future that a future version must change
  one of these types then the refactor will be required to add a shim for the future version and the shared implementation will need to be updated to handle the new type.
- **Version-free core.** Domain types and the shared implementation are
  written in no protocol version's terms. 
- **A shim per version per service, doing only wire ↔ core translation**, each
  constructed over the *same instance* of the shared implementation. If you
  are duplicating logic rather than mapping types, the change belongs in the
  shared implementation or the core, not the shim.
- **A shim validates nothing.** Input it cannot translate (an unset union, a
  missing member) goes down as "absent" for the shared implementation to
  reject, so every version fails a bad request with the same error in the same
  order.
- **The shared implementation never branches on the version.** The call
  context may record which version a call arrived on (for metrics); behaviour
  that differs per version is a forked server with extra steps.
- **Only shims may import wire/generated types.** Enforce it mechanically — a
  lint or test that fails when anything else does.
- **The handshake service is the exception** that stays per-version, because
  its echo is version-specific by nature.
- The shim layer (or protocol layer) is responsible for basic validation, if
  a field is marked as mandatory for a given version, then omitting it should
  result in a clear error indication. The shared implementation is responsible for validating the business logic of the request and response, and returning appropriate error indications if the request or response is invalid.
- The shim layer is responsible for mutating any request or response to make it
  work with the shared implementation.

**The client mirrors it.** A connection type that can only negotiate; a
transport bound to one negotiated version, obtainable only by naming that
version; one dialer module per version, translation only. Select the dialer
with an **exhaustive match over the version enumeration**, so declaring a
version that has no dialer fails to build (where the language cannot check
exhaustiveness, a test that iterates every declared version). **Never fall
back to an older version's dialer**: a version negotiated and reported while
its traffic travels on older routes makes the per-version counter read
backwards — and that counter is the retirement gate.

**Tests that protect the contract — do not weaken them:**

- a server newer than this client build still connects;
- a client compiled without the served-set still decodes and negotiates;
- for **every** declared version, each operation reaches a route naming that
  version, asserted on what the server *received*. Iterate the enumeration so
  there is no list to extend;
- a test-only extra version registered beside the real one in the server's own
  tests, proving concurrent serving before it is relied on.

## 5. Version lifecycle
Version expiry must be planned. A service must not create a versioned api without
understanding the conditions in which a particular version is no longer needed. 
It is recommended that the service records usage of versions but it is not required. The service should have a plan for retiring versions and should communicate that plan to clients.
It is not acceptable to keep a version alive indefinitely, as this will lead to technical debt and increased maintenance costs. Any version can be retired if it is no longer needed, but the service should consider the impact on clients and provide a reasonable notice period before retiring a version,
versions do not need to be retired in any particular order.
See `references/lifecycle.md` before doing adding or retiring versions.
