# rp serverless workers
Show an endpoint's live workers: ids, states, placement, versions.

```
rp serverless workers <id> [--json]
```

## ARGUMENTS

```
  <id>             endpoint id — from `rp serverless list`
```

## OPTIONS

```
  --json           print the raw envelope (workers + summary + endpointVersion)
```

## NOTES
  Human mode prints a status histogram (total/running/idle/init/throttled/
  unhealthy) on stderr, then tables the active workers.

**API:** `GET /v2/serverless/{id}/workers`

