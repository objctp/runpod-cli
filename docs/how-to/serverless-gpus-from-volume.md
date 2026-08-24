# How-to: scope a serverless endpoint to a network volume's datacentre

A common aim is to put a serverless endpoint's GPUs in the same datacentre as a
network volume, so workers can attach it with low latency. This page explains
what `--gpus-from-volume` does and does **not** do, and the recipe that actually
pins the endpoint to the volume's datacentre.

## What `--gpus-from-volume` does and does not do

`--gpus-from-volume <name>` is a GPU-picker shortcut. It resolves the named
network volume to its datacentre (only to log it) and then returns the
**account-wide** in-stock serverless GPU types that appear in a hard-coded
four-type preference list:

- NVIDIA RTX 4000 Ada Generation
- NVIDIA GeForce RTX 4090
- NVIDIA L4
- NVIDIA A40

The datacentre is **logged but never used to filter** the GPU list. So the flag
does not "scope GPUs to the volume's sibling datacentre"; it hands back a small,
fixed-preference slice of the account-wide serverless stock. The four-type
allowlist is built into the CLI and you cannot change it via flags.

What actually pins the endpoint to the volume's datacentre is
`--network-volume <name>` (or `--network-volume-id <id>`): it resolves the
volume's datacentre and sets the endpoint's `dataCenterIds` to it. That is the
only thing that scopes placement.

There is therefore **no single flag** that both scopes GPUs to a volume's
datacentre and picks those GPUs by that datacentre's stock. The practical recipe
combines two flags.

## Steps

1. Confirm where the volume lives and what is in stock. Read the volume's
   datacentre with `rp volume gpus <name>` (or `rp volume list` — the
   `DATACENTER` column), then check the account-wide serverless stock.
   Remember the stock query is **not** per-datacentre — it tells you a type
   is in stock somewhere on your account:

   ```
   $ rp volume gpus hf-cache
   $ rp stock gpu --product SERVERLESS --json | jq -r '.[] | select(.id=="NVIDIA L4")'
   ```

   For a genuine per-datacentre, per-type view, use
   `rp stock dc --json | jq '.[] | select(.id=="<dc>") | .gpuAvailability'`.

2. Create the endpoint, pinning it to the volume's datacentre with
   `--network-volume`, and choosing the GPU explicitly with `--gpu`:

   ```
   $ rp serverless create --name my-endpoint --template tmpl_abc \
       --network-volume hf-cache \
       --gpu "NVIDIA L4" \
       --workers-min 0 --workers-max 3 --idle 600
   ```

   The endpoint's `dataCenterIds` is set from `hf-cache`'s datacentre, so workers
   are placed there.

3. (Optional) If you prefer the CLI's built-in four-type preference instead of
   choosing a GPU, add `--gpus-from-volume <name>`. In the `rp serverless create`
   path this flag only takes effect when a `--network-volume` is also given, and
   the GPU list it yields is still account-wide, not datacentre-filtered:

   ```
   $ rp serverless create --name my-endpoint --template tmpl_abc \
       --network-volume hf-cache --gpus-from-volume hf-cache \
       --workers-min 0 --workers-max 3 --idle 600
   ```

   Here `hf-cache`'s datacentre still comes from `--network-volume`; the GPUs are
   the account-wide in-stock members of the four-type allowlist.

## Notes

- `--network-volume` is what scopes the endpoint to a datacentre (it sets
  `dataCenterIds`). `--gpus-from-volume` is only a GPU picker and does not scope
  placement.
- In `rp serverless create`, `--gpus-from-volume` is ignored unless a
  `--network-volume` / `--network-volume-id` is also supplied (the GPU-picker
  branch runs only after the datacentre has been resolved). In
  `rp serverless create --hub-id`, it runs regardless but is still account-wide.
- The four types returned by `--gpus-from-volume` are fixed in the CLI; pass
  `--gpu` to pick outside that list.
- Verify the volume's datacentre (`rp volume gpus`, `rp volume list`) and the
  in-stock types (`rp stock gpu --product SERVERLESS`, or the
  `gpuAvailability` array from `rp stock dc --json`) before booking.
