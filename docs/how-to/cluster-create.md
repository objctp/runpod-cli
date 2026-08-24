# How-to: provision a multi-node homogeneous pod cluster with one command

This is a worked task. The reference page (`rp doc cluster create`) documents the
individual flags; this page shows them composed into a single provisioning call
and clears up what "homogeneous" and "required" mean in practice.

Goal: stand up `N` identical pods — one GPU type, one GPU count, one container
config — as a single named fleet with one `rp cluster create` call.

## Why one command

A cluster is a single named, single-datacentre fleet of identical pods. The
`--gpu`, `--gpu-count`, and `--pod-count` flags are fleet-wide: every member
gets the same compute shape, so you describe the whole fleet, not each node.
RunPod provisions the nodes from a single request. Afterwards the name is the
only mutable field (`rp cluster update` is a rename); compute, type, and
container config are fixed at create.

## Steps

1. (Optional but recommended) Confirm the GPU type is in stock before you
   commit to it. `rp cluster create --gpu` takes a single display name with
   no fallback list, so an out-of-stock type fails later rather than
   degrading gracefully. `--min-count` is per host, so match it to the
   per-node GPU count you plan to request:

   ```
   $ rp stock gpu --product CLUSTER --min-count 8 --json
   ```

   The `id` field (e.g. `NVIDIA H100 80GB HBM3`) is what you pass to
   `--gpu`.

2. Create the cluster. Only `--name`, `--type`, and `--gpu` are mandatory;
   `--pod-count` defaults to 2, so a 2-node cluster needs no extra count flag:

   ```
   $ rp cluster create --name tr-1 --type TRAINING \
       --gpu "NVIDIA H100 80GB HBM3" \
       --pod-count 4 --gpu-count 8 \
       --dc EU-RO-1 \
       --network-volume-id vol_xyz --volume-path /runpod-volume \
       --start-ssh true
   ```

   - `--type` must be `APPLICATION`, `TRAINING`, `SLURM`, or `RAY`.
   - `--gpu-count` defaults to 1; `--pod-count` must be at least 2.
   - `--dc` accepts a comma-separated preferred list, but placement stays
     single-DC; omit it to let the scheduler choose.
   - `--network-volume-id` + `--volume-path` mount the same volume on every node;
     `--volume-path` defaults if omitted.
   - `--start-ssh` / `--start-jupyter` enable the service on all members.

3. Inspect the fleet once it is up. The `pods` verb takes the cluster **by
   id**, so read the id from `rp cluster list` first:

   ```
   $ rp cluster list
   $ rp cluster pods <cluster_id>
   ```

## Notes

- Creation is idempotent by name: if a cluster of that name already exists, the
  CLI prints its id and skips the POST. Pass `--force` to send the request
  regardless.
- Clusters do not support private registries — there is no `--registry` flag on
  `rp cluster create`. Use a public image or a network volume for your build.
- `--template-id` seeds container config defaults; any explicit flag still wins.
- Because the fleet is homogeneous by construction, there is no per-node flag —
  you cannot mix GPU types or counts within one cluster.
