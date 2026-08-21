# rp volume gpus
List GPU types in stock, with the volume's datacentre noted.

```
rp volume gpus <name> [--gpu <id,…>] [--json]
```

## ARGUMENTS

```
  <name>        network volume name — from `rp volume list`
```

## OPTIONS

```
  --gpu <id,…>  restrict the table to these GPU type ids
  --json        print the raw API response
```

## NOTES
  The catalogue is account-wide, not per-datacentre: v2 exposes no per-DC
  stock field. The command prints the volume's datacentre for context and
  then the same figures `rp stock gpu` shows, so read the table as "what is
  in stock at all", not "what is in stock beside this volume".
  Columns are GPU, VRAM_GB, STOCK and SECURE_PRICE. SECURE_PRICE is the
  secure-cloud rate per GPU per hour; community pricing is not shown.
  The catalogue is queried for POD and SERVERLESS together, so a type listed
  here may still be unavailable for one of the two.
  --gpu filters client-side after the fetch, so an id that matches nothing
  yields an empty table rather than an error.

## EXAMPLES

```
  rp volume gpus models
  rp volume gpus models --gpu "NVIDIA L4,NVIDIA GeForce RTX 4090"
```

**API:** `GET /v2/catalog/gpus  (include=AVAILABILITY, product=POD,SERVERLESS)`

