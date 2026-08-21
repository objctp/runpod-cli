# rp serverless get
Show one endpoint's full record and scaling config.

```
rp serverless get <id> [--jq <filter>] [--json]
```

## ARGUMENTS

```
  <id>             endpoint id — from `rp serverless list`
```

## OPTIONS

```
  --jq <filter>    jq filter applied to the record
  --json           print the raw API response instead of pretty JSON
```

**API:** `GET /v2/serverless/{id}`

