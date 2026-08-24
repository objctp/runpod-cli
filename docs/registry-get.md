# rp registry get
Show one registry credential's full record.

```
rp registry get <id> [--jq <filter>] [--json]
```

## Arguments

```
  <id>             credential id — from `rp registry list`
```

## Options

```
  --jq <filter>    jq filter applied to the record
  --json           print the raw API response instead of pretty JSON
```

**API:** `GET /v2/registries/{id}`

