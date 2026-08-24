# How-to: create a network volume and attach it to a pod by name

This is a worked task that spans a few commands. The reference pages
(`rp doc pod create`, `rp doc volume create`) document the individual flags;
this page shows them composed into one workflow.

Goal: create a network volume and mount it on a pod, addressing the volume by
its name rather than copying an id by hand.

## Steps

1. Create the volume. `rp volume create` is idempotent by `--name` and prints
   the new (or existing) id on stdout, so capture it directly:

   ```
   $ VOL_ID=$(rp volume create --name hf-cache --size 100 --dc EU-RO-1)
   ```

2. Attach that id to the pod with `--network-volume-id`, placing the pod in
   the volume's datacentre with `--dc` (the mount requires co-location). A
   pod takes one mount kind, so `--volume-gb` and `--network-volume-id` are
   mutually exclusive:

   ```
   $ rp pod create --name loader --image runpod/pytorch:2.2.0 \
       --gpu "NVIDIA L4" --dc EU-RO-1 \
       --network-volume-id "$VOL_ID" --volume-path /runpod-volume --ssh
   ```

## Notes

- `rp pod create` accepts a network volume **only by id** through
  `--network-volume-id`; it has no by-name flag, so the CLI cannot resolve a
  name for you on the pod path. Two ways to get the id from the name:
  capture it at create time (as in step 1 — re-running with the same `--name`
  returns the existing id), or resolve it later:

  ```
  $ VOL_ID=$(rp volume list --json --jq '.[] | select(.name=="hf-cache") | .id')
  ```

- `--volume-path` (alias `--volume-mount-path`) sets the on-pod mount point;
  it defaults to `/workspace` when omitted.
- The volume's datacentre is fixed at create and cannot move; the pod that
  mounts it must be placed in the same datacentre.
- On the serverless path the name lookup happens for you — see
  [Resolve a network volume by name and attach it to a serverless
  endpoint](endpoint-attach-volume-by-name.md).
- Only some datacentres expose the S3 API. A volume created in one that does
  not still works as a pod mount, but `rp volume sync` / `rp volume ls` will
  not reach it — `rp stock dc` marks the ones that do.
