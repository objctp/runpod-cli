# rp stock gpu
List GPU types with price and live availability.

```
rp stock gpu [--product <p,…>] [--min-count N]
                    [--cloud SECURE|COMMUNITY] [--min-cuda <ver>]
                    [--vram-gb N] [--stock NONE|LOW|MEDIUM|HIGH]
                    [--cuda <ver>] [--sort <column>] [--json]
```

## Options

```
  --product <p,…>           POD, CLUSTER or SERVERLESS, comma-separated
                            (default: POD,SERVERLESS)
  --min-count N             only types with at least N GPUs free on one host
                            (minimum 1)
  --cloud SECURE|COMMUNITY  keep only types offered on that tier
  --min-cuda <ver>          minimum CUDA version, major or major.minor
  --vram-gb N               keep only types with at least N GB of VRAM
                            (--vram is accepted as an alias)
  --stock <level>           keep only types whose STOCK is that level
  --cuda <ver>              keep only types with that CUDA version available
  --sort <column>           order rows by ID, DISPLAY, VRAM_GB, CLOUD,
                            SECURE_PRICE, COMMUNITY_PRICE, STOCK or CUDA
  --json                    print the raw API response
```

## Notes
  The ID column is the value `rp pod create --gpu` and
  `rp serverless create --gpu` take. Ids are display names containing
  spaces, so quote them.
  STOCK is availability for the product and cloud you asked about, so one
  card can read differently under --product POD and --product SERVERLESS.
  CLOUD lists the tiers a type is offered on: "SECURE, COMMUNITY" when both,
  or just "SECURE" / "COMMUNITY"; a dash means neither.
  SECURE_PRICE and COMMUNITY_PRICE are the per-GPU hourly rates for each
  tier; a dash ("-") means that tier is not offered (gated on the
  secure/community flags, not on the price value — the API can return a
  non-zero price for an unoffered tier).
  CUDA lists the available CUDA versions (truncated to two plus "+N more");
  a dash means none are advertised. It is the same ceiling --min-cuda filters
  against.
  --vram-gb / --vram is a minimum: a type with more VRAM than N still passes.
  All filters and --sort apply to BOTH the table and --json, so the two views
  always show the same types.
  --min-count is per host: it asks for N of that GPU in one machine, not N
  across the fleet. The floor is 1, so 0 or a negative is a usage error.
  --min-cuda takes 12 or 12.1; any other shape is rejected before the call.

## Examples

```
# Show secure-cloud GPUs with at least two in stock
$ rp stock gpu --cloud SECURE --min-count 2

# Show serverless GPUs with CUDA 12.4 or newer
$ rp stock gpu --product SERVERLESS --min-cuda 12.4
```

**API:** `GET /v2/catalog/gpus  (include=AVAILABILITY)`

