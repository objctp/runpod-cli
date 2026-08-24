# How-to: build a GPU fallback list for a serverless endpoint from in-stock types

This is a worked task that spans several commands. The reference pages
(`rp doc stock gpu`, `rp doc serverless create`, `rp doc volume gpus`) document
the individual flags; this page shows them composed into one workflow.

Goal: pick the GPU types currently in stock for serverless, order them into a
fallback chain (cheapest first, or by any preference you choose), and pass that
ordered list to `rp serverless create --gpu`.

## Why order matters

`rp serverless create --gpu` takes a comma-separated list of GPU **display
names** (the `ID` column from `rp stock gpu`). The CLI does not reorder the
list: it maps each name to its serverless pool id and emits them, in your
order, into the endpoint's `gpu.pools` array. The pools array is therefore
sent in your order — first listed type first — so build the list in the
priority you want before passing it.

## Steps

1. Query the in-stock serverless GPUs you care about. All four filters are
   valid:

   ```
   $ rp stock gpu --product SERVERLESS --min-count 1 --cloud SECURE --min-cuda 12.1 --json
   ```

   The `--json` payload is the raw `gpus` array. Each entry has `id` (the
   display name, e.g. `NVIDIA L4`), `price.secure` (a number), and
   `availability` (a categorical **string** — `HIGH`/`MEDIUM`/`LOW`/`NONE`,
   not a count).

2. Extract the `id`s and order them into your fallback chain. Because
   `price` is an object (`.price.secure`) and `availability` is non-numeric,
   sort by price only — do **not** sort by `.price` or by `.availability`:

   ```
   $ rp stock gpu --product SERVERLESS --min-count 1 --json \
       | jq -r 'sort_by(.price.secure // 1e9) | .[].id' | paste -sd, -
   # => NVIDIA L4,NVIDIA GeForce RTX 4090,NVIDIA A40,...
   ```

   (`// 1e9` keeps a null-priced type at the expensive end of the sort.) To
   hand-pick a priority instead of sorting, edit the `jq` output or build the
   comma list directly. The order you feed in is the order the endpoint
   receives.

3. Create the endpoint with the ordered list. Quote it so the commas survive
   the shell:

   ```
   $ rp serverless create --name my-endpoint --template tmpl_abc \
       --gpu "$(rp stock gpu --product SERVERLESS --min-count 1 --json \
                 | jq -r 'sort_by(.price.secure // 1e9) | .[].id' | paste -sd, -)" \
       --workers-min 0 --workers-max 3 --idle 600
   ```

## Notes

- Use the manual query (steps 1–3) when you want a price- or
  preference-ordered fallback chain.
- `--min-count` is per host (N of that GPU in one machine), floored at 1.
- `availability` cannot be used to rank "most available first" — it is a
  category string, not a numeric stock count.
- For a convenience shortcut with less control, `--gpus-from-volume` picks
  in-stock types from a fixed four-type preference list (account-wide stock,
  never your ordering). It is covered in
  [Scope a serverless endpoint to a network volume's datacentre](serverless-gpus-from-volume.md);
  inspect the candidate types for a volume with `rp volume gpus <name>`
  (its `GPU` column holds the same `.id` names `--gpu` takes, and
  `--gpu <id,id>` restricts the list).
