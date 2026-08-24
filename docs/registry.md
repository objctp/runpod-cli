# rp registry
Container-registry credentials and ECR access delegations.
A registry auth entry lets a pod or endpoint pull a private image without
embedding a password in the container. An ECR delegation links an AWS account
to Runpod so images can be pulled from a private Elastic Container Registry
without a stored credential at all. Both surfaces use REST API v2.

```
rp registry <verb> [flags]
```

## Commands

- [`rp registry delegations`](registry-delegations.md) — Manage ECR access delegations between an AWS account and Runpod.
- [`rp registry list`](registry-list.md) — List your registry credentials: id and name.
- [`rp registry get`](registry-get.md) — Show one registry credential's full record.
- [`rp registry create`](registry-create.md) — Store a container-registry credential for pulling private images.
- [`rp registry delete`](registry-delete.md) — Delete a registry credential.
