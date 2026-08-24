# rp cluster pods
List a cluster's member pods as a table: id, name, status.

```
rp cluster pods <id> [--json]
```

## Arguments

```
  <id>             cluster id — from `rp cluster list`
```

## Options

```
  --json           print the raw API response (full pod records)
```

## Notes
  The list endpoint returns the full pod objects (same shape as `rp pod get`),
  so this is a quick fleet view. `rp cluster get <id>` carries the lightweight
  member summary (total + counts by status).

**API:** `GET /v2/clusters/{id}/pods`

