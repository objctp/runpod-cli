# rp serverless update
Change an endpoint's workers, GPU pool, registry, template, name, or scaling.

```
rp serverless update <id> [--workers-min N] [--workers-max N]
                           [--idle S] [--gpu <types>] [--exclude-gpu <type,..>]
                           [--gpu-count N]
                           [--registry <id>] [--template-id <id>]
                           [--name <n>] [--scale-by delay|requests]
                           [--scale-threshold N] [--scaler-type QUEUE_DELAY|REQUEST_COUNT]
                           [--scaler-value V]
```

## Arguments

```
  <id>             endpoint id — from `rp serverless list`
```

## Options

```
  --workers-min N  new minimum worker count
  --workers-max N  new maximum worker count
  --idle S         workers.idleTimeout (ignored with REQUEST_COUNT scaling)
  --gpu <types>    GPU type ids for the worker pool (alias: --gpu-id)
  --exclude-gpu <type,..>  GPU type ids to subtract from the selected pools
                           (comma-separated; requires --gpu in the same call)
  --gpu-count N    GPUs per worker (default: 1)
  --registry <id>  registry credential for a private image (alias: --registry-auth-id)
  --template-id <id>   swap the endpoint's template (PATCH field templateId;
                       the API applies the template's container config)
  --name <n>           rename the endpoint (PATCH field name)
  --scale-by delay|requests   runpodctl coercion: maps to --scaler-type
                              (delay→QUEUE_DELAY, requests→REQUEST_COUNT)
  --scale-threshold N  runpodctl coercion: maps to --scaler-value (the
                       queueDelay seconds, or requestCount)
  --scaler-type QUEUE_DELAY|REQUEST_COUNT   scaling policy (rp native flag)
  --scaler-value V      scaling threshold (rp native flag)
  --json           print the raw API response
```

## Notes
  At least one flag is required; with none, the command exits with a usage
  error rather than sending an empty PATCH.
  A --gpu change re-resolves pool ids from the type names.
  --exclude-gpu subtracts GPU type ids from the selection made by --gpu
  (no inclusive allowlist exists). Update semantics follow the API's PATCH:
  exclusions require pools in the same PATCH, and resending pools WITHOUT
  --exclude-gpu clears any existing gpu.excludedTypes — the CLI warns about
  that wipe so an implicit clearing stays visible. Validation is client-side
  (each excluded type must belong to one of the selected pools; the API
  silently accepts unknown exclusions).
  --scale-by / --scale-threshold are coercion aliases (runpodctl spelling)
  that feed the same scaling object as rp's --scaler-type / --scaler-value.

**API:** `PATCH /v2/serverless/{id}`

