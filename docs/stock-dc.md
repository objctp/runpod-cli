# rp stock dc
List datacentres with GPU stock and S3-API support.

```
rp stock dc [--json] [--s3] [--global-network] [--volume-type <t,…>]
                    [--compliance <c,…>] [--region <r,…>]
```

## Options

```
  --json          print the raw v2 datacentre records (post-filter)
  --s3            keep only S3-API-enabled datacentres
  --global-network  keep only datacentres on Runpod's global network
  --volume-type <t,…>  keep only datacentres supporting at least one listed
                       network-volume tier (e.g. STANDARD,HIGH_PERFORMANCE)
  --compliance <c,…>   keep only datacentres carrying at least one listed
                       certification (e.g. SOC_2_TYPE_2)
  --region <r,…>       keep only datacentres in at least one listed region
                       (e.g. EU,NA,AS) — the REGION column, case-insensitive.
                       Accepts abbreviations (eg: NA, EU) or the full names
                       (eg: NORTH_AMERICA, ASIA)
```

## Notes
  Filters combine as a logical AND; within a comma list they are OR. All flags
  apply to BOTH the table and --json, so the two views always show the same
  datacentres (--json omits the S3_API column, which is a CLI-side join).
  The DATACENTER column is the id `rp pod create --dc` and
  `rp volume create --dc` take. (The v2 `name` field is the same value in
  practice and is not shown as a separate column.)
  GPUS counts how many GPU types have any stock there, not how many cards
  are free.
  GLOBAL_NETWORK marks datacentres that support global networking — Runpod's
  private, cross-datacenter pod-to-pod network (pods reach each other over
  *.runpod.internal without opening ports to the public internet). It is
  unrelated to the S3_API column.
  COMPLIANCE lists the certifications the datacentre carries (e.g.
  SOC_2_TYPE_2), comma-separated; blank where none are advertised.
  NETWORK_VOLUME_TYPES lists the network-volume tiers the datacentre supports
  (e.g. STANDARD, HIGH_PERFORMANCE), comma-separated; blank where none are
  advertised. The tier constrains the kind of volume `rp volume create` can
  place there.
  S3_API marks the datacentres whose network volumes expose the
  S3-compatible API — the ones `rp volume sync` can reach.
  That column is NO-V2-EQUIVALENT: v2 carries no S3 field anywhere, so it is
  joined in from the GraphQL dataCenters query — the same resolver
  `rp volume create` guards on — with an offline snapshot behind it. The
  column therefore stays live where GraphQL is reachable and still renders
  when it is not.
  --json prints the v2 datacentre records alone: S3_API is a CLI-side join
  and is absent from that payload.

## Examples

```
# Datacentres that are BOTH S3-API enabled AND on the global network
$ rp stock dc --s3 --global-network

# Datacentres that support the HIGH_PERFORMANCE volume tier
$ rp stock dc --volume-type HIGH_PERFORMANCE
```

**API:** `GET /v2/catalog/datacenters  (include=GPU_AVAILABILITY,CPU_AVAILABILITY)`

