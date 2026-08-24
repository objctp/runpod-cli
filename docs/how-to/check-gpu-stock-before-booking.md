# How-to: check live GPU stock across all datacentres before booking a pod

This is a worked task that spans a few commands. The reference pages
(`rp doc stock gpu`, `rp doc stock dc`, `rp doc pod create`) document the
individual flags; this page shows them composed into a pre-booking check.

Goal: confirm the GPU type you want is available somewhere, see which
datacentres have GPU stock, and book a pod pinned to a datacentre — or let the
scheduler choose one for you.

## Steps

1. Find which GPU types are in stock. `rp stock gpu` lists one row per GPU
   type with a `STOCK` column — the fleet-wide availability for the product
   and cloud you asked about. Filter to pod-relevant hardware and a secure
   cloud, and require at least one free on a host:

   ```
   $ rp stock gpu --product POD --min-count 1 --cloud SECURE
   ```

   The `ID` column holds the display name `rp pod create --gpu` takes — names
   contain spaces, so quote them. `--product` defaults to `POD,SERVERLESS`;
   use `--product SERVERLESS` for serverless availability, or
   `--min-cuda 12.1` to filter by CUDA version.

2. See which datacentres have GPU stock. `rp stock dc` prints a table keyed on
   the `DATACENTER` id, with `REGION` and `GPUS` (how many GPU *types* have
   any stock there, not how many cards), plus the `S3_API`, `GLOBAL_NETWORK`,
   `NETWORK_VOLUME_TYPES`, and `COMPLIANCE` columns:

   ```
   $ rp stock dc
   ```

   The `DATACENTER` value is exactly what `rp pod create --dc` takes.

3. Get the per-datacentre, per-GPU-type breakdown. `rp stock dc --json`
   prints the datacentre records **including** the `gpuAvailability` array,
   which lists each GPU type and its availability for every location. This is
   the source of truth for "which GPU types are in stock where" — the
   datacentre dimension is already carried here, so no second query or
   client-side join is needed:

   ```
   $ rp stock dc --json | jq '.[].gpuAvailability'
   ```

4. Book the pod. Pass the chosen type and datacentre:

   ```
   $ rp pod create --name dev --image runpod/pytorch:2.2.0 \
       --gpu "NVIDIA L4" --dc EU-RO-1
   ```

   Omit `--dc` and the scheduler places the pod wherever that GPU type is
   free.

## Notes

- `rp stock gpu` is the aggregate view by construction: its `STOCK` column is
  per-GPU-type availability across the fleet. There is no `--dc` or `--all`
  flag on `rp stock gpu`, and no option that sums the `rp stock dc`
  rows into a fleet total — use `rp stock gpu` directly rather than summing
  datacentre rows. (`rp stock cpus --dc` does filter by datacentre, but that
  is a different verb.)
- There is no `rp` command that prints one flat cross-DC-per-GPU table, but
  `rp stock dc --json` already carries the datacentre dimension inside
  `gpuAvailability`, so a single call answers "which GPU types are in stock
  where" — and `rp stock gpu`'s `STOCK` column alone cannot tell you *where*
  a type is free.
- For a network-volume-backed pod, the datacentre is fixed by the volume. Use
  step 3 to confirm the GPU type you want is in stock in that specific DC
  before booking.
