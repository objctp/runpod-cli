# rp cluster create
Provision a homogeneous multi-node cluster.

```
rp cluster create --name <n> --type <kind> --gpu <type>
                        [--pod-count N] [--gpu-count N] [flags]
```

## OPTIONS

```
  --name <n>                        cluster name (required)
  --type <kind>                     APPLICATION|TRAINING|SLURM|RAY (required)
  --gpu <type>                      one GPU type for every pod (required)
  --gpu-count N                     GPUs per pod (default: 1; minimum 1)
  --pod-count N                     number of pods (minimum 2, default: 2)
  --dc <id,…>                       preferred datacentres; omit to let the
                                   scheduler place the cluster (single DC)
  --image <ref>                     Docker image for every pod
  --container-disk-gb N             ephemeral container disk, GB (minimum 1)
  --ports <a/b,…>                   exposed ports, each as port/protocol
  --env K=V                         environment variable; repeatable
  --start-cmd <a,b,…>               arguments passed to the container entrypoint
  --network-volume-id <id>          attach one network volume to every pod
  --volume-path <path>              mount path for the network volume
  --template-id <id>                seed container config from a template id
  --start-ssh true|false            provision SSH with your account key
  --start-jupyter true|false       start Jupyter on every member pod
  --force                           create even when the name is taken
```

## NOTES
  A cluster is homogeneous: every pod is identical, so a single --gpu type,
  --gpu-count, and --pod-count describe the whole fleet. --pod-count must be at
  least 2 (a cluster is multi-node by definition).
  Creation is idempotent by name, like `rp volume create` and
  `rp serverless create`: where a cluster of that name already exists, the CLI
  prints its id and skips the POST. --force sends the request regardless.
  Only the name can change afterwards — `rp cluster update` is a rename, and
  compute shape, type, and container config are fixed at create.
  Clusters do not yet support private registries (no --registry): the v2
  create request has no registry field. Use a public image or a network volume
  for your build.
  --template-id seeds the container config as defaults; any explicit flag value
  still wins, and the template's id is recorded on the cluster.

## EXAMPLES

```
  rp cluster create --name tr-1 --type TRAINING \
      --gpu "NVIDIA H100 80GB HBM3" --pod-count 4 --gpu-count 8
  rp cluster create --name ray --type RAY --gpu "NVIDIA L4" \
      --image runpod/ray:latest --network-volume-id vol_xyz
```

**API:** `POST /v2/clusters`

