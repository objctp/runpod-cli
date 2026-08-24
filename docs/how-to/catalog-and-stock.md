# How-to: browse the public template catalog and check GPU availability per datacentre

This is a worked task that spans a few commands. The reference pages
(`rp doc catalog list`, `rp doc template search`, `rp doc stock dc`,
`rp doc stock gpu`) document the individual flags; this page shows them
composed into one workflow.

Goal: list the public community templates you can clone into a pod or
serverless endpoint, and find out which datacentres currently have GPUs in
stock so you can pin `--dc` (or choose a region for a cluster) with
confidence.

## Steps

1. List the public catalog. `--limit`, `--cursor`, `--jq`, and `--json` are
   all valid:

   ```
   $ rp catalog list --limit 50
   ```

   Each row carries `id`, `name`, `image`, `serverless`, and `public`. To
   pull just the names:

   ```
   $ rp catalog list --json --jq '.[].name'
   ```

   To keep only the serverless-ready entries:

   ```
   $ rp catalog list --json --jq 'map(select(.serverless))'
   ```

   To filter your *own* templates by name substring instead, use
   `rp template search <name-substring>` (case-insensitive) — that matches
   against your account's templates, not the public catalog:

   ```
   $ rp template search vllm
   ```

2. See which datacentres have GPUs in stock. `rp stock dc` returns a table
   with the `DATACENTER` id, its `NAME`/`REGION`, `GPUS` (how many GPU
   *types* have any stock there, not how many cards), and `S3_API`:

   ```
   $ rp stock dc
   ```

   The `DATACENTER` value is exactly what `rp pod create --dc`,
   `rp volume create --dc`, and `rp cluster create --dc` take.

3. Get per-datacentre GPU detail. `rp stock dc --json` prints the datacentre
   records **including** the `gpuAvailability` array, which lists each GPU
   type and its per-datacentre availability for every location:

   ```
   $ rp stock dc --json
   ```

   This is the source of truth for "which GPU types are in stock where" — the
   `gpuAvailability` field already carries the datacentre dimension, so no
   second query is needed.

## Notes

- `rp template` and `rp catalog` are different resources. `rp template` lists
  *yours* — the private/serverless container configs saved under your
  account. `rp catalog list` reads the **public** community catalog, which is
  list-only (no create/get/delete of its own). Copy an id from the catalog
  into `rp pod create --template-id` or `rp serverless create --template-id`.
- Use `rp stock dc --json` and read `gpuAvailability` for per-datacentre
  stock. `rp stock gpu --product SERVERLESS --json` is the wrong tool for
  that: it reports one availability category per GPU type, not a datacentre
  breakdown.
- `rp stock gpu` is still the right tool when you want the *list* of in-stock
  GPU display names (the `ID` column) to pass to `rp pod create --gpu` or
  `rp serverless create --gpu`.
- `S3_API` is shown only in the table, not in `--json`.
