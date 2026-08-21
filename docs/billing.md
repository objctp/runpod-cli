# rp billing
Spend reports for pods, serverless, clusters and volumes.
Every verb reads the same v2 billing envelope — a records array of per-bucket
totals plus a metadata object — over one time window, and the four window
flags apply to all of them. Verbs differ only in the product they report and
whether they narrow to a single resource id. Serverless spend lives at
/billing/serverless; /billing/endpoints is the separate *public endpoint*
product, reached as `rp billing public-endpoints`.

```
rp billing <verb> [flags]
```

## COMMANDS

- [`rp billing pods`](billing-pods.md) — Report pod spend, optionally for one pod.
- [`rp billing serverless`](billing-serverless.md) — Report serverless spend, optionally for one endpoint.
- [`rp billing public-endpoints`](billing-public-endpoints.md) — Report spend on the public endpoint product.
- [`rp billing clusters`](billing-clusters.md) — Report instant cluster spend, optionally for one cluster.
- [`rp billing volumes`](billing-volumes.md) — Report network volume spend, optionally for one volume.
- [`rp billing all`](billing-all.md) — Report aggregated spend across every product.
