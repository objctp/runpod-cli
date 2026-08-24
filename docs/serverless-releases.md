# rp serverless releases
Show an endpoint's release history and rollout.

```
rp serverless releases <id> [--json]
```

## Arguments

```
  <id>             endpoint id — from `rp serverless list`
```

## Options

```
  --json           print the raw envelope (releases + rollout + endpointVersion)
```

## Notes
  Human mode prints the rollout summary (workers on latest / total, percent)
  on stderr, then tables the releases with a per-release field diff.

**API:** `GET /v2/serverless/{id}/releases`

