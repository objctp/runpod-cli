# rp pod create
Create a pod from an image, optionally seeded by a template.

```
rp pod create --image <ref> --name <n>
                     (--gpu <type> | --cpu-flavor <id> --vcpu N) [flags]
```

## OPTIONS

```
  --image <ref>                  Docker image reference (required unless
                                 --template-id is given)
  --template-id <id>             seed the container config from a template id;
                                 makes --image optional
  --name <n>                     pod name (required)
  --gpu <type>                   GPU type id — see `rp stock gpu` (alias: --gpu-id)
  --gpu-count N                  GPUs to attach (default: 1)
  --cpu-flavor <id>              CPU flavour id — see `rp stock cpus`
  --vcpu N                       vCPUs; a power of two, minimum 2
  --compute-type GPU|CPU         runpodctl coercion: selects the --gpu path, or
                                 the --cpu-flavor/--vcpu path (requires the
                                 matching flags); adds no data of its own
  --cloud SECURE|COMMUNITY       hardware tier (default: SECURE) (alias: --cloud-type)
  --dc <id,…>                    preferred datacentres; omit to let the
                                 scheduler place the pod (alias: --data-center-ids)
  --volume-gb N                  host-local persistent volume, GB (minimum 10)
                                 (alias: --volume-in-gb)
  --network-volume-id <id>       attach an existing network volume instead
  --volume-path <path>           mount path for either volume kind
                                 (default: /workspace) (alias: --volume-mount-path)
  --container-disk-gb N          ephemeral container disk, GB (minimum 1)
                                 (alias: --container-disk-in-gb)
  --global-networking true|false give the pod a private IP reachable across
                                 datacentres; omit for the API default (false)
  --public-ip                    request a public IP; community-cloud pods are
                                 not publicly routable by default, so set this
                                 to reach them directly (alias of runpodctl's
                                 --public-ip; maps to supportPublicIp)
  --ports <a/b,…>                exposed ports, each as port/protocol
  --env K=V                      environment variable; repeatable; NOT aliased to runpodctl's --env (a single JSON object) — the repeatable K=V shapes differ
  --start-cmd <a,b,…>            arguments passed to the container entrypoint
                                 (alias: --docker-args)
  --template <id>                template whose container config seeds the pod
  --registry <id>                registry credential for a private image
                                 (alias: --registry-auth-id)
  --ssh                          start the pod with runpodctl-style SSH
                                 access enabled (requires registered SSH keys)
  --min-cuda-version <x.y>       require a GPU driver with at least this CUDA
                                 version (e.g. 12.1); GPU pods only
  --interruptible                 create a spot (interruptible) pod; the server
                                 bids the on-demand price unless --bid-per-gpu
                                 is also set (GPU pods only)
  --bid-per-gpu <n>               max $/GPU-hour to pay for a spot pod; implies
                                 --interruptible; must be > 0 (GPU pods only)
```

## NOTES
  A pod is either a GPU pod or a CPU pod: pass --gpu or --cpu-flavor, never
  both. The CLI enforces "exactly one": it rejects a create that sets neither
  or that sets both, so the failure is a local usage error, not an API error.
  --name is required by the API and checked by the CLI up front, so a missing
  --name fails locally before any request.
  --image is required even with --template, and always wins over the
  template's own image. --template-id is the v2-native equivalent: pass the
  template id directly and the API applies its container config, which lets you
  omit --image entirely.
  Storage is one kind or the other: --volume-gb is host-local, pinned to the
  machine and lost if that host fails, whilst --network-volume-id is durable
  and must already live in the pod's datacentre. CPU pods reject --volume-gb.
  The mount kind is fixed at create — `rp pod update` cannot switch it.
  --compute-type is runpodctl's spelling for the same choice: `--compute-type
  GPU --gpu <t>` and `--compute-type CPU --cpu-flavor <id> --vcpu <n>` are
  equivalent to the canonical rp invocations; it carries no data and dies if
  the matching flags are absent.
  --gpu takes a single type in v2. A comma-separated list is still accepted,
  but only the first entry is used and a warning is printed.
  --global-networking needs an NVIDIA GPU and a datacentre that supports it,
  so it is rejected alongside --cpu-flavor.
  v2 has no templateId parameter. --template fetches the template and spreads
  its container config as defaults.
  --interruptible and --bid-per-gpu create a spot pod: --bid-per-gpu sets the
  maximum $/GPU-hour you will pay and implies --interruptible; given alone,
  --interruptible bids the on-demand price. Both are GPU-only — a spot pod is
  preempted when capacity is reclaimed, so checkpoint long work. The bid must
  be a positive number. The request is sent to REST v2 first; if that server
  does not yet advertise the spot fields it falls back to the deprecated
  GraphQL podRentInterruptable mutation, warning as it does so. The bridge is
  temporary and will be removed once v2 supports spot pods natively.
  --min-cuda-version is a GPU-only field: a value not matching X.Y (e.g. 12.1)
  is rejected up front, and a valid value is applied only to GPU pods — on a
  CPU pod it is silently ignored (there is no gpu block to carry it). It is
  mutually exclusive with any allowed-CUDA-versions selection, which rp does
  not expose.
  --force is accepted and ignored. Unlike `rp volume create` and
  `rp template create`, pod creation is not idempotent by name, so re-running
  this command creates a second pod.

## EXAMPLES

```
  rp pod create --name trainer --image runpod/pytorch:2.2.0 \
    --gpu "NVIDIA GeForce RTX 4090" --container-disk-gb 50
  rp pod create --name cpu-box --image alpine --cpu-flavor cpu5c --vcpu 4
  rp pod create --name shared --image alpine --gpu "NVIDIA L4" \
    --network-volume-id vol_xyz --volume-path /runpod-volume
  rp pod create --name spot-trainer --image runpod/pytorch:2.2.0 \
    --gpu "NVIDIA RTX 4090" --bid-per-gpu 0.20
```

**API:** `POST /v2/pods`

