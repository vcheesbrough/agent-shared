# Protocol version lifecycle

Companion to `../SKILL.md`.

## Introducing version `vN`

These steps are recommended, not required. The order is the useful part: it is
what makes a half-finished change fail loudly instead of shipping.

1. **Copy the newest wire definition to a new `vN` namespace** (its own
   package / path prefix, hence its own routes). Make the change there, and
   only there. Every existing version's definition stays untouched.
2. **Generate/expose the `vN` wire types** alongside the existing versions'.
3. **Write the `vN` shims.** Reuse the shared adapter code for everything `vN`
   leaves unchanged, and write new adapter code only for what it changes —
   never by calling another version's shim. The shim adapts `vN`'s wire
   contract to the shared implementation and does `vN`'s basic validation; new
   business behaviour goes in the shared implementation or the core, expressed
   version-free.
4. **Register the `vN` routes on the server, leaving every existing
   registration in place**, each `vN` shim constructed over the same instance
   of the shared implementation the older shims use.
5. **Teach the clients to dial `vN`:**
   - declare `vN` in the version enumeration, *before* the existing members
     (ordering is preference order, most preferred first). This says only that
     clients can *speak* `vN`;
   - the build now fails (or the iterate-all-versions test does) at every
     transport that cannot dial it — that failure is the point;
   - fix it by writing a `vN` dialer per transport. Do **not** silence it by
     returning an older version's dialer.
6. If any client can be deployed before the server, it must support multiple
   versions — typically with the same shim approach. This is not expected to
   be common.

## Retiring version `vK`

The server should not retire a version that a client still uses, but it is
free to do so.

The server should add a deprecation date to the version in its handshake
response, and stop serving the version after that date. None of this is
required: the server may drop a version abruptly if it needs to — a version in
which a security flaw is discovered is likely to be dropped immediately.

Retiring is removing the version's routes, its shim, and its entry in the
handshake's list. The routes then fall to the catch-all, which answers with
the version-not-served error; a client still connected on `vK` re-handshakes
once and carries on with another version, or aborts if it has none in common
(`../SKILL.md` §1.6). Adapter code shared with other versions stays; only what
`vK` alone used is deleted.
