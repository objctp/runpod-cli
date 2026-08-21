# rp cluster
Clusters: multi-node homogeneous pod fleets (REST v2).
A cluster is a single named, single-datacentre fleet of identical pods — every
member shares one compute shape (GPU type, GPUs per pod, pod count) and one
container config. Create provision the whole fleet; rename is the only mutable
field afterwards, so compute, type, and container config are fixed at create.
The v2 REST plane backs every verb here (no GraphQL equivalent).

```
rp cluster <verb> [flags]
```

## COMMANDS

- [`rp cluster list`](cluster-list.md) — List your clusters: id, name, type, node count, created date.
- [`rp cluster get`](cluster-get.md) — Show one cluster's full record, including its compute shape and member summary.
- [`rp cluster create`](cluster-create.md) — Provision a homogeneous multi-node cluster.
- [`rp cluster update`](cluster-update.md) — Rename a cluster.
- [`rp cluster delete`](cluster-delete.md) — Delete a cluster and tear down its member pods.
- [`rp cluster pods`](cluster-pods.md) — List a cluster's member pods as a table: id, name, status.
