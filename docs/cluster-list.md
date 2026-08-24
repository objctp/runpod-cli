# rp cluster list
List your clusters: id, name, type, node count, created date.

```
rp cluster list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## Options

```
  --limit N      return at most N clusters
  --cursor <c>   offset to resume from; pairs with --limit
  --jq <filter>  jq filter applied to the array
  --json         print the raw API response
```

## Notes
  node count is the cluster's podCount (the homogeneous fleet size), not the
  number currently provisioned — see `rp cluster pods <id>` for live counts.

**API:** `GET /v2/clusters`

