# rp stock gpu
List GPU types with price and live availability.

```
rp stock gpu [--product <p,…>] [--min-count N]
                    [--cloud SECURE|COMMUNITY] [--min-cuda <ver>] [--json]
```

## OPTIONS

```
  --product <p,…>           POD, CLUSTER or SERVERLESS, comma-separated
                            (default: POD,SERVERLESS)
  --min-count N             only types with at least N GPUs free on one host
                            (minimum 1)
  --cloud SECURE|COMMUNITY  hardware tier; omit for both
  --min-cuda <ver>          minimum CUDA version, major or major.minor
  --json                    print the raw API response
```

## NOTES
  The ID column is the value `rp pod create --gpu` and
  `rp serverless create --gpu` take. Ids are display names containing
  spaces, so quote them.
  STOCK is availability for the product and cloud you asked about, so one
  card can read differently under --product POD and --product SERVERLESS.
  SECURE_PRICE is the secure-cloud rate per GPU per hour; community pricing
  is not in this table.
  --min-count is per host: it asks for N of that GPU in one machine, not N
  across the fleet. The floor is 1, so 0 or a negative is a usage error.
  --min-cuda takes 12 or 12.1; any other shape is rejected before the call.

## EXAMPLES

```
  rp stock gpu --cloud SECURE --min-count 2
  rp stock gpu --product SERVERLESS --min-cuda 12.4
```

**API:** `GET /v2/catalog/gpus  (include=AVAILABILITY)`

