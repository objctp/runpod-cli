# rp registry delegations
Manage ECR access delegations between an AWS account and RunPod.

```
rp registry delegations <verb> [flags]
```

## NOTES
  A delegation links an ECR repository so private images can be pulled without
  a stored registry credential. Sub-verbs: list, create, revoke.

**API:** `GET /v2/registries/delegations`

## COMMANDS

- [`rp registry delegations list`](registry-delegations-list.md) — List your ECR access delegations.
- [`rp registry delegations create`](registry-delegations-create.md) — Link an ECR repository for credential-free private-image pulls.
- [`rp registry delegations revoke`](registry-delegations-revoke.md) — Remove an ECR access delegation.
