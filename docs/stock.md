# rp stock
Catalogue of GPU types, CPU flavours, and datacentres.
Read-only lookups against the API v2 catalogue: what hardware exists, what it
costs, and where it is in stock right now. The ids printed here are the ones
`rp pod create` takes for --gpu, --cpu-flavor and --dc. Every column is v2
REST bar the S3-API column of `rp stock dc`, which has no v2 field and stays
on GraphQL.

```
rp stock <verb> [flags]
```

## Commands

- [`rp stock gpu`](stock-gpu.md) — List GPU types with price and live availability.
- [`rp stock cpus`](stock-cpus.md) — List reservable CPU instances with price and availability.
- [`rp stock dc`](stock-dc.md) — List datacentres with GPU stock and S3-API support.
- [`rp stock gpu`](stock-gpu.md) — List GPU types with price and live availability.
- [`rp stock cpus`](stock-cpus.md) — List reservable CPU instances with price and availability.
- [`rp stock dc`](stock-dc.md) — List datacentres with GPU stock and S3-API support.
