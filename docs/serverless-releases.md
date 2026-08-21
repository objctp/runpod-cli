# rp serverless releases
Show an endpoint's release history and rollout.

```
rp serverless releases <id> [--json]
```

## ARGUMENTS

```
  <id>             endpoint id — from `rp serverless list`
```

## OPTIONS

```
  --json           print the raw envelope (releases + rollout + endpointVersion)
```

## NOTES
  Human mode prints the rollout summary (workers on latest / total, percent)
  on stderr, then tables the releases with a per-release field diff.

**API:** `GET /v2/serverless/{id}/releases`

