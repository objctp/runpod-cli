# rp registry get
Show one registry credential's full record.

```
rp registry get <id> [--jq <filter>] [--json]
```

## ARGUMENTS

```
  <id>             credential id — from `rp registry list`
```

## OPTIONS

```
  --jq <filter>    jq filter applied to the record
  --json           print the raw API response instead of pretty JSON
```

**API:** `GET /v2/registries/{id}`

