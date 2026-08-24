# rp serverless health
Show a deployed endpoint's operational health: worker and job counts.

```
rp serverless health <id> [--json]
```

## Arguments

```
  <id>             endpoint id — from `rp serverless list`
```

## Options

```
  --json           print the raw health envelope (workers + jobs)
```

## Notes
  The call rides the data plane (api.runpod.ai/v2), distinct from the
  control-plane REST. Human mode prints a worker/job histogram to stdout.

## Examples

```
# Ping an endpoint's health
$ rp serverless health end_abc
```

**API:** `GET /{id}/health`

