# rp pod get
Show one pod's full record, including runtime ports and utilisation.

```
rp pod get <id> [--jq <filter>] [--json]
```

## Arguments

```
  <id>             pod id — from `rp pod list`
```

## Options

```
  --jq <filter>    jq filter applied to the record
  --json           print the raw API response instead of pretty JSON
```

## Notes
  runtime is null until the pod reaches RUNNING, which is why
  `rp ssh info` reports no connection line for a stopped pod.

**API:** `GET /v2/pods/{id}`

