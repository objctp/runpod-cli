# rp registry delegations list
List your ECR access delegations.

```
rp registry delegations list [--json]
```

## OPTIONS

```
  --json           print the raw API response
```

## NOTES
  The table shows each delegation's id, name, repository, tag, AWS region and
  creation time.

**API:** `GET /v2/registries/delegations`

