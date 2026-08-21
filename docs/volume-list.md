# rp volume list
List your network volumes as a table: id, name, size, dataCenter.

```
rp volume list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## OPTIONS

```
  --limit N      return at most N volumes
  --cursor <c>   offset to resume from; pairs with --limit
  --jq <filter>  jq filter applied to the array
  --json         print the raw API response
```

## NOTES
  dataCenter is where the volume lives for good. A volume cannot move, so
  anything that mounts it must be scheduled in that same datacentre.
  size is the provisioned capacity in GB, not the space in use. Billing
  follows the provisioned figure.
  Paging is client-side: the whole list is fetched, then sliced. When output
  is truncated the next cursor is printed to stderr, leaving stdout clean.

**API:** `GET /v2/network-volumes`

