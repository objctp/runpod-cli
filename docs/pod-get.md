# rp pod get
Show one pod's full record, including runtime ports and utilisation.

```
rp pod get <id> [--jq <filter>] [--json]
```

## ARGUMENTS

```
  <id>             pod id — from `rp pod list`
```

## OPTIONS

```
  --jq <filter>    jq filter applied to the record
  --json           print the raw API response instead of pretty JSON
```

## NOTES
  runtime is null until the pod reaches RUNNING, which is why
  `rp ssh info` reports no connection line for a stopped pod.

**API:** `GET /v2/pods/{id}`

