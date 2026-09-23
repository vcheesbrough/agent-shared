# Deploying the `OTEL_*` variables on this estate

Companion to `../SKILL.md` §2. **Recommended on this estate, not required by
the contract.** The contract says the standard variables are the whole
configuration interface; this is how they reach a container here.

## A layer of their own

The variables live in sovereign-config, in a layer of their own per product
environment — `/<product>/devops/<env>/otel/`, holding the `OTEL_*` leaves as
direct children and nothing else — rendered as one more layer on the deploy
command the environment already uses:

```
sovereign-config render /<product>/devops/<env>/compose /<product>/devops/<env>/otel -- <deploy>
```

Layers are read in order and overlaid onto the deploy step's environment, and
compose passes the names into the service's `environment:` block. The compose
file never holds a value, so telemetry is retargeted by a write to the store,
not a commit. Keeping telemetry out of the compose layer means it is reviewed,
listed and revoked on its own, and has the same shape in every product.

Two properties of `render` shape the layer:

- **Only a layer's direct children become variables**, so nothing is nested
  beneath it.
- **A layer that contributes nothing fails the deploy.** An environment without
  telemetry leaves the layer off the render command rather than empty; an
  environment that keeps the layer but wants it silent stores
  `OTEL_SDK_DISABLED=true` in it.

## Aliases for shared facts

**A leaf that states the same fact as another leaf is an alias of it**, not a
copy. The upstream collector address is one stored value under a shared path
(`/observability/otlp-endpoint`, or wherever the estate keeps platform-wide
facts), and every product environment's `OTEL_EXPORTER_OTLP_ENDPOINT` — the
ingest pair's included — is `alias_add`-ed from it, so moving the collector is
one write that cannot leave a product behind.

Aliases rather than a shared layer, because a product's render connection is
confined to its own subtree and reaches the shared value only through a path
inside it.

The same holds within a product: `OTEL_SERVICE_NAME` is one fact across its
environments. `OTEL_RESOURCE_ATTRIBUTES` is the leaf that genuinely differs per
environment, because `deployment.environment.name` lives in it; it is stored
per environment and aliased nowhere.
