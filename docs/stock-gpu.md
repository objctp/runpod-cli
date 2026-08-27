# rp stock gpu
List GPU types with price and live availability.

```
rp stock gpu [--product <p,…>] [--min-count N]
                    [--cloud SECURE|COMMUNITY] [--dc <id>] [--min-cuda <ver>]
                    [--vram-gb N] [--stock NONE|LOW|MEDIUM|HIGH]
                    [--cuda <ver>] [--sort <column>] [--json]
```

## Options

```
  --product <p,…>           POD, CLUSTER or SERVERLESS, comma-separated
                            (default: POD,SERVERLESS)
  --min-count N             only types with at least N GPUs free on one host
                            (minimum 1)
  --cloud SECURE|COMMUNITY  keep only types offered on that tier; also drops
                            the opposite tier's price column (SECURE hides
                            COMMUNITY_PRICE, and vice versa)
  --dc <id>                 keep only types offered in this datacentre
                            (case-insensitive); also makes STOCK region-accurate
                            for that datacentre instead of a cross-DC aggregate
  --min-cuda <ver>          minimum CUDA version, major or major.minor
  --vram-gb N               keep only types with at least N GB of VRAM
                            (--vram is accepted as an alias)
  --stock <level>           keep only types whose STOCK is that level
  --cuda <ver>              keep only types with that CUDA version available
  --sort <column>           order rows by ID, DISPLAY, VRAM_GB, CLOUD,
                            SECURE_PRICE, COMMUNITY_PRICE, STOCK or CUDA
                            (VRAM is accepted as an alias for VRAM_GB)
  --hide <cols>             drop columns from the table (display-only; never
                            filters rows or --json). Comma-separated,
                            case-insensitive: any of ID, DISPLAY, VRAM_GB,
                            CLOUD, SECURE_PRICE, COMMUNITY_PRICE, STOCK, CUDA,
                            DATACENTERS (e.g. --hide DISPLAY,SECURE_PRICE)
  --json                    print the raw API response
```

## Notes
  The ID column is the value `rp pod create --gpu` and
  `rp serverless create --gpu` take. Ids are display names containing
  spaces, so quote them.
  STOCK is shown only with --dc, and is that datacentre's own availability
  (region-accurate). The DATACENTERS column always carries the per-datacentre
  breakdown.
  CLOUD lists the tiers a type is offered on: "SECURE, COMMUNITY" when both,
  or just "SECURE" / "COMMUNITY"; a dash means neither. With --cloud the
  column is omitted, since every shown row is on that tier.
  SECURE_PRICE and COMMUNITY_PRICE are the per-GPU hourly rates for each
  tier; a dash ("-") means that tier is not offered (gated on the
  secure/community flags, not on the price value — the API can return a
  non-zero price for an unoffered tier). With --cloud these columns are
  pruned: --cloud SECURE shows only SECURE_PRICE, --cloud COMMUNITY only
  COMMUNITY_PRICE, and the other (all-dash) column is omitted.
  CUDA lists the available CUDA versions (truncated to two plus "+N more");
  a dash means none are advertised. It is the same ceiling --min-cuda filters
  against.
  DATACENTERS lists the datacentres that offer this GPU with stock
  (availability != NONE), sorted by id and truncated to two ids plus "+N
  more"; a dash means none are stocked. It is the same per-datacentre
  availability the API returns under include=AVAILABILITY, so it already
  honours --product, --cloud and --min-count. With --dc the requested
  datacentre is omitted from the list (you already scoped to it).
  --vram-gb / --vram is a minimum: a type with more VRAM than N still passes.
  --hide is display-only: it removes columns from the table but leaves the row
  set and the --json payload untouched, so it is unrelated to filtering.
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

