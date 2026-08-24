# How-to: resolve a network volume by name and attach it to a serverless endpoint

When you attach a network volume to a serverless endpoint you do not need to
look the volume's id up yourself. `rp serverless create` accepts the volume by
name and resolves it internally, then pins the endpoint to that volume's
datacentre. A pod is different: `rp pod create` takes a volume only by id —
that path is covered in
[Create a network volume and attach it to a pod by name](attach-volume-to-pod-by-name.md).

## Steps

1. Attach a network volume to a serverless endpoint by name. Pass the volume
   name to `--network-volume <name>`; the CLI resolves it to an id and scopes
   the endpoint to the volume's datacentre for you:

   ```
   $ rp serverless create --name my-endpoint --template tmpl_abc \
       --network-volume hf-cache --gpus-from-volume hf-cache \
       --workers-min 0 --workers-max 3 --idle 600
   ```

   `--gpus-from-volume` here picks in-stock serverless GPU types from a fixed
   four-type preference list — account-wide stock, not filtered by the
   volume's datacentre; the pinning comes entirely from `--network-volume`
   (see [Scope a serverless endpoint to a network volume's
   datacentre](serverless-gpus-from-volume.md)).

2. (Optional) Attach by id instead, when you already hold one. The by-id
   equivalents are `--network-volume-id <id>` (one) and
   `--network-volume-ids <id,id>` (several, template path only):

   ```
   $ rp serverless create --name my-endpoint --template tmpl_abc \
       --network-volume-id vol_abc123 --gpu "NVIDIA L4" \
       --workers-min 0 --workers-max 3 --idle 600
   ```

   To read a volume's id or datacentre from its name in one line:

   ```
   $ rp volume list --json --jq '.[] | select(.name=="hf-cache") | .id'
   $ rp volume list --json --jq '.[] | select(.name=="hf-cache") | .dataCenter'
   ```

## Notes

- The serverless path resolves the name automatically: `--network-volume
  <name>` is the by-name flag, and the by-id flags are there for when you
  already know the id.
- The endpoint lives in the same datacentre as the volume — enforced for you,
  since the datacentre is pinned from the volume; there is no separate `--dc`
  step to perform.
- Only some datacentres expose the S3 API. A volume created in one that does
  not still attaches to an endpoint, but `rp volume sync` / `rp volume ls`
  will not be able to reach it — `rp stock dc` marks the ones that do.
