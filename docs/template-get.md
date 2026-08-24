# rp template get
Show one template's full record, including its container config.

```
rp template get <id> [--jq <filter>] [--json]
```

## Arguments

```
  <id>             template id — from `rp template list`
```

## Options

```
  --jq <filter>    jq filter applied to the record
  --json           print the raw API response instead of pretty JSON
```

## Notes
  The record carries the container config that `rp pod create --template`
  spreads: image, args, disk, ports, env and registry.
  This verb takes an id, not a name; find the id with `rp template search`.

**API:** `GET /v2/templates/{id}`

