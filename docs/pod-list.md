# rp pod list
List your pods as a table: id, name, image, status, cost.

```
rp pod list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## OPTIONS

```
  --limit N        return at most N pods
  --cursor <c>     offset to resume from; pairs with --limit
  --jq <filter>    jq filter applied to the array
  --public-ip      show only pods that currently expose a public IP
  --json           print the raw API response
```

## NOTES
  status is one of PROVISIONING, STARTING, RUNNING, EXITED, ERROR or
  TERMINATED.
  Paging is client-side: the whole list is fetched, then sliced. When output
  is truncated the next cursor is printed to stderr, leaving stdout clean.

**API:** `GET /v2/pods`

