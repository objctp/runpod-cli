# How-to: create a scale-to-zero endpoint scoped to a volume's datacentre

This is a worked task that spans a few commands. The reference pages
(`rp doc serverless create`, `rp doc volume`) document the individual flags;
this page shows them composed into one workflow.

Goal: deploy a serverless endpoint that scales to zero when idle and is
automatically co-located with a network volume, so its workers read cached
files from disk in the volume's own datacentre.

## Steps

1. Create (or reuse) a network volume. Its datacentre is what the endpoint
   will be pinned to:

   ```
   $ rp volume create --name hf-cache --size 100 --dc EU-RO-1
   ```

2. Create the endpoint. `--network-volume` attaches the volume *by name* and
   is the flag that actually scopes the endpoint to the volume's datacentre
   (it sets `dataCenterIds` from the volume's datacentre). `--gpus-from-volume`
   resolves in-stock GPU types from the account-wide serverless catalogue and
   overrides any `--gpu` you passed:

   ```
   $ rp serverless create --name my-endpoint --template tmpl_abc \
       --network-volume hf-cache --gpus-from-volume hf-cache \
       --workers-min 0 --workers-max 3 --idle 600 --flashboot
   ```

## Notes

- `--workers-min 0` is the scale-to-zero switch; `--idle 600` keeps workers
  warm for ten minutes before the last one scales down (ignored under
  `--scaler-type REQUEST_COUNT`); `--flashboot` speeds cold starts.
- The endpoint is idempotent by `--name`: re-running the same `create` prints
  the existing endpoint's id and skips the POST.
- `--network-volume` and `--gpus-from-volume` are distinct roles:
  `--gpus-from-volume` only takes effect when a volume is also attached
  (`--network-volume` / `--network-volume-id`), since that is what supplies
  the datacentre. Without an attached volume, `--gpus-from-volume` alone
  leaves the GPU pool empty and the create fails. When both `--gpu` and
  `--gpus-from-volume` are given, `--gpus-from-volume` wins.
- GPU availability is account-wide, not datacentre-specific, so the resolved
  types are not guaranteed to be the only stock in that datacentre — they are
  simply the highest-priority in-stock types from the catalogue. The full
  placement story is in
  [Scope a serverless endpoint to a network volume's datacentre](serverless-gpus-from-volume.md);
  for the flag-by-flag reference, `rp doc serverless create`.
