# rp registry create
Store a container-registry credential for pulling private images.

```
rp registry create --name <n> --username <u> [--password <p>]
```

## Options

```
  --name <n>                credential name (required)
  --username <u>            registry username (required)
  --password <p>            registry password; if omitted, prompts interactively
```

## Notes
  --password is visible in process listings (`ps`) and shell history; prefer
  the interactive prompt by omitting it.
  The credential is not idempotent by name, so re-running create adds a second
  entry rather than updating the first.

**API:** `POST /v2/registries`

