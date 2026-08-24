# rp stock dc
List datacentres with GPU stock and S3-API support.

```
rp stock dc [--json]
```

## Options

```
  --json  print the raw API response
```

## Notes
  The DATACENTER column is the id `rp pod create --dc` and
  `rp volume create --dc` take.
  GPUS counts how many GPU types have any stock there, not how many cards
  are free.
  S3_API marks the datacentres whose network volumes expose the
  S3-compatible API — the ones `rp volume sync` can reach.
  That column is NO-V2-EQUIVALENT: v2 carries no S3 field anywhere, so it is
  joined in from the GraphQL dataCenters query — the same resolver
  `rp volume create` guards on — with an offline snapshot behind it. The
  column therefore stays live where GraphQL is reachable and still renders
  when it is not.
  --json prints the v2 datacentre records alone: S3_API is a CLI-side join
  and is absent from that payload.

**API:** `GET /v2/catalog/datacenters  (include=GPU_AVAILABILITY,CPU_AVAILABILITY)`

