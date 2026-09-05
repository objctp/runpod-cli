# rp cost-center assign
Tag resources to a cost center, moving them out of any previous one.

```
rp cost-center assign <name> <id>…
```

## Arguments

```
  <name>           cost center to tag into (create it first)
  <id>…            one or more pod / endpoint / volume / cluster ids
```

## Notes
  A resource sits in exactly one cost center: assigning an already-tagged id
  moves it. Ids are classified by reading the pod, serverless, volume and
  cluster lists (one pass), and a type is remembered per id so spend can bill
  against the right product. An id no list knows is still recorded — its type
  stays unknown and spend then bills it against every product, which still
  sums correctly because an id only appears in its own product's report.
  Tagging is local, so it works on terminated or deleted resources too; their
  billing history keeps resolving by id.

## Examples

```
# Put a pod and an endpoint into the same project bucket
$ rp cost-center assign rag-pipeline pod_abc123 ep-7f2a
```

**API:** `GET /v2/pods, GET /v2/serverless, GET /v2/network-volumes,`

     GET /v2/clusters (id classification only)
