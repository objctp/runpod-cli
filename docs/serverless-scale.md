# rp serverless scale
Set an endpoint's worker bounds and idle timeout in one call.

```
rp serverless scale <id> --min N --max N [--idle S]
```

## Arguments

```
  <id>             endpoint id — from `rp serverless list`
```

## Options

```
  --min N          minimum worker count
  --max N          maximum worker count
  --idle S         workers.idleTimeout (ignored with REQUEST_COUNT scaling)
  --json           print the raw API response
```

## Notes
  At least one of --min/--max/--idle is required.

**API:** `PATCH /v2/serverless/{id}`

