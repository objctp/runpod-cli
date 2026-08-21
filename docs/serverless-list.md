# rp serverless list
List your endpoints: id, name, worker bounds and idle timeout.

```
rp serverless list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## OPTIONS

```
  --limit N        return at most N endpoints
  --cursor <c>     offset to resume from; pairs with --limit
  --jq <filter>    jq filter applied to the array
  --json           print the raw API response
```

## NOTES
  The table shows the configured worker min/max and idle timeout; live worker
  counts come from `rp serverless workers <id>`.

**API:** `GET /v2/serverless`

