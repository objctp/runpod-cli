# rp registry delegations list
List your ECR access delegations.

```
rp registry delegations list [--json]
```

## Options

```
  --json           print the unwrapped delegations array as JSON
```

## Notes
  The table shows each delegation's id, name, repository, tag, AWS region and
  creation time.

**API:** `GET /v2/registries/delegations`

