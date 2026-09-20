# Protocol version lifecycle

Companion to `../SKILL.md`. Both procedures are ordered on purpose: the order
is what makes a half-finished change fail loudly instead of shipping.

## Introducing version `vN`

These steps are recommended but not required.

1. **Copy the newest wire definition to a new `vN` namespace** (its own
   package / path prefix, hence its own routes). Make the breaking change
   there, and only there. Every existing version's definition stays untouched.
2. **Generate/expose the `vN` wire types** alongside the existing versions'.
3. **Write the `vN` ↔ core shims** by copying the previous version's shims and
   pointing them at the `vN` types. Translation only, validate nothing; if the
   breaking change needs new behaviour, it goes in the shared implementation
   or the core, expressed version-free.
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
6. **Add `vN` to the server's served-versions set — last.** This is what
   advertises it, so the routes must already exist. The unauthenticated
   handshake allowlist and the metric label derive from this set and need no
   separate edit; if they do need one, fix that first.
7. If any clients can be deployed before the server then they must support
   multiple versions, typically they will use the same 'shim' approach to 
   do this, it is expected this is not common.

## Retiring version `vK`

It is preferred that the server will not retire a version that a client still 
uses however it is free to do so if it wishes.

The server 'should' add a deprecation date to the old version in the get versions
request, after that date it should stop supporting that version, however none of 
this is required and the server may drop a version abrutly if it needs to do so.