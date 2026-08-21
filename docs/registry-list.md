# rp registry list
List your registry credentials: id and name.

```
rp registry list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## OPTIONS

```
  --limit N        return at most N credentials
  --cursor <c>     offset to resume from; pairs with --limit
  --jq <filter>    jq filter applied to the array
  --json           print the raw API response
```

**API:** `GET /v2/registries`

