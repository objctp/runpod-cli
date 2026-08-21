# rp cluster get
Show one cluster's full record, including its compute shape and member summary.

```
rp cluster get <id> [--jq <filter>] [--json]
```

## ARGUMENTS

```
  <id>             cluster id — from `rp cluster list`
```

## OPTIONS

```
  --jq <filter>    jq filter applied to the record
  --json           print the raw API response instead of pretty JSON
```

**API:** `GET /v2/clusters/{id}`

