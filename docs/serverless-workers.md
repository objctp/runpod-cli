# rp serverless workers
Show an endpoint's live workers: ids, states, placement, versions.

```
rp serverless workers <id> [--json]
```

## Arguments

```
  <id>             endpoint id — from `rp serverless list`
```

## Options

```
  --json           print the raw envelope (workers + summary + endpointVersion)
```

## Notes
  Human mode prints a status histogram (total/running/idle/init/throttled/
  unhealthy) on stderr, then tables the active workers.

**API:** `GET /v2/serverless/{id}/workers`

