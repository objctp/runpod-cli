# How-to: deploy a serverless endpoint from a Hub listing

This is a worked task that skips template-building entirely. The reference
pages (`rp doc hub search`, `rp doc hub get`, `rp doc serverless create`)
document the individual flags; this page shows them composed into one deploy.

Goal: run a serverless endpoint from an official Hub worker (for example
`worker-vllm`) without building a private template — `rp` fetches the
listing's image and default configuration and creates the endpoint for you.

## Steps

1. Find the listing. Hub listings live in the marketplace, not your account,
   so browse them with the `hub` commands:

   ```
   $ rp hub search "vllm"
   $ rp hub list --category inference          # browse instead of search
   $ rp hub get <listing-id>
   ```

   `hub get` shows the listing's build image and default configuration —
   useful for seeing which env vars it expects before you deploy.

2. Deploy from the listing. `--hub-id` and `--template` are alternative
   sources for the same endpoint — pick one. `--name` is required, and the
   endpoint is idempotent by name:

   ```
   $ rp serverless create --name my-endpoint --hub-id <listing-id> \
       --network-volume hf-cache --gpus-from-volume hf-cache \
       --workers-min 0 --workers-max 3 --idle 600
   ```

   `--network-volume` attaches the volume by name and pins the endpoint to
   that volume's datacentre. `--gpus-from-volume` picks in-stock serverless
   GPU types from a fixed four-type preference list — account-wide stock, not
   filtered by the volume's datacentre — and overrides `--gpu` (see
   [Scope a serverless endpoint to a network volume's datacentre](serverless-gpus-from-volume.md)).

## Notes

- Pass exactly one source: `--hub-id` *or* `--template`. If you add
  `--template-id` alongside `--hub-id`, it is silently ignored rather than
  rejected.
- Not every template-path flag reaches the hub path. `--flashboot`,
  `--network-volume-ids`, and `--execution-timeout` are template-only and
  silently dropped here; only `--network-volume` (singular, by name or id)
  attaches a volume. `--idle` is still honoured unless you switch to
  `--scaler-type REQUEST_COUNT`.
- `--env K=V` **replaces** the listing's default env vars entirely when
  given — the listing's defaults survive only when `--env` is omitted.
  (On the `--template` path, by contrast, `--env` merges over the
  template's env.)
- A `--hub-id` deploy still needs GPU capacity. If you pass neither `--gpu`
  nor `--gpus-from-volume`, `rp` falls back to the GPU list the listing
  declares; if the listing declares none, the command tells you to pass
  `--gpu`.
