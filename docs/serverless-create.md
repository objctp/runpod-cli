# rp serverless create
Create a serverless endpoint from a template or a Hub listing.

```
rp serverless create --template <id>|--template-id <id> --name <n>
                            [--gpu <type,..>] [--exclude-gpu <type,..>]
                            [--network-volume <name> | --network-volume-id <id>
                             | --network-volume-ids <id,id>]
                            [--type QUEUE|LOAD_BALANCER] [flags]
```

## Options

```
  --template <id>               template id to deploy (required unless --hub-id
                                or --template-id); spread client-side so flags
                                can override the template's container config
  --template-id <id>            v2-native template id (alternative to
                                --template); the API applies the template's
                                container config, so flags cannot override it
  --hub-id <listing-id>         deploy from a Hub listing (requires --name;
                                mutually exclusive with --template)
  --name <n>                    endpoint name (required); idempotent by name
  --gpu <type,..>               GPU type ids (comma-separated) for the pool
                                (alias: --gpu-id)
  --exclude-gpu <type,..>       GPU type ids (comma-separated) to subtract
                                from the selected pools
  --gpus-from-volume <name>     pick in-stock serverless GPU types from a
                                fixed four-type preference list (account-wide
                                stock, not filtered by the volume's
                                datacentre); overrides --gpu — placement is
                                pinned by --network-volume, not this flag
  --network-volume <name>       attach a network volume by name
  --network-volume-id <id>      attach a network volume by id
  --network-volume-ids <id,id>  attach several network volumes by id
  --type QUEUE|LOAD_BALANCER    endpoint type (default: QUEUE)
  --workers-min N               minimum worker count
  --workers-max N               maximum worker count
  --idle S                      workers.idleTimeout; ignored with
                                REQUEST_COUNT scaling
  --gpu-count N                 GPUs per worker (default: 1)
  --flashboot                   enable FlashBoot (boolean flag)
  --env K=V                     environment variable; repeatable; merged over
                                the template's env on the --template path;
                                NOT aliased to runpodctl's --env (a single
                                JSON object) — the shapes differ
  --scaler-type QUEUE_DELAY|REQUEST_COUNT   scaling policy
  --scaler-value V              scaling threshold (default: 4s / 1 request)
  --execution-timeout <s>       per-job timeout, sent as milliseconds
  --registry <id>               registry credential for a private image
                                (alias: --registry-auth-id)
  --cost-center <name>          tag the endpoint into a local cost center at
                                create (see: rp cost-center); the center must
                                already exist
  --force                       skip the name idempotency check
  --min-cuda-version <ver>      accepted but ignored: v2 keeps it only as a
                                /catalog/gpus filter
```

## Notes
  --name is required by the live v2 spec on both the --template and --hub-id
  paths; the CLI checks it up front, so a missing --name fails locally before
  any request rather than as an API error.
  --type and --scaling are required by the live v2 spec; when omitted the CLI
  defaults type to QUEUE and scaling to QUEUE_DELAY with a 4s delay, so a
  create neither errors nor needs them spelled out.
  --env is merged over the template's environment on the --template path, so
  `rp serverless create --template X --env K=V` overrides per key.
  --idle (workers.idleTimeout) is rejected for REQUEST_COUNT scaling and is
  ignored with a warning when set.
  --min-cuda-version is accepted and dropped with a warning: v2 has no
  create-side CUDA-version field, only the /catalog/gpus filter.
  GPU selection is pool-based: --gpu maps the type ids to pool ids and the
  API places workers anywhere inside those pools. --exclude-gpu subtracts
  GPU type ids from that selection; there is no inclusive allowlist. The
  subtraction is validated client-side — each type must belong to one of
  the selected pools (the API silently accepts unknown exclusions, so a
  typo would otherwise exclude nothing).
  Opting out of a partitionable MiG slice is the exclusion use case: e.g.
  `--gpu "NVIDIA L4" --exclude-gpu "NVIDIA RTX PRO 6000 Blackwell Server
  Edition MIG 1g.24gb"` pins the AMPERE_24 pool (L4 is a member) and drops
  its 24 GB MiG member. See `rp stock gpu --mig` for the MiG ids.
  --cost-center tags the new endpoint into a local cost center for
  per-project spend (`rp cost-center spend`); the center must exist, and the
  check runs before the endpoint is created. The tagging is local — Runpod's
  own Cost Centers are console-only.

## Examples

```
# Deploy a serverless endpoint from a template
$ rp serverless create --name ocr --template tmpl_abc --gpu "NVIDIA L4"

# Same pool, but opt out of its 24 GB MiG slice
$ rp serverless create --name ocr --template tmpl_abc --gpu "NVIDIA L4" \
    --exclude-gpu "NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb"

# Deploy from a Hub listing
$ rp serverless create --name diff --hub-id hub_xyz --gpu "NVIDIA A40"
```

**API:** `POST /v2/serverless`

