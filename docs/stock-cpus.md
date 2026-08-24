# rp stock cpus
List CPU flavours with price and availability.

```
rp stock cpus [--dc <id>] [--json]
```

## Options

```
  --dc <id>   keep only flavours stocked in this datacentre (case-insensitive)
  --json      print the raw API response
```

## Notes
  The ID column is the value `rp pod create --cpu-flavor` takes.
  VCPU is the flavour's valid vcpuCount range; --vcpu must be a power of two
  inside it.
  RAM_GB_VCPU is the RAM allotted per vCPU and SECURE_PRICE_VCPU the
  secure-cloud hourly rate per vCPU, so both scale with the vCPU count you
  ask for.
  This verb takes one optional filter and no others: --dc <id> keeps only
  the flavours stocked in that datacentre (case-insensitive). The filter
  applies to BOTH the table and --json, so the two views always show the
  same flavours.
  DATACENTERS lists every datacentre the flavour is stocked in, but the
  table column is truncated to the first two ids followed by "+N more"
  (e.g. "EU-CZ-1, EU-NL-1 +12 more") to keep the row readable; the full
  list is always in --json. Because filtering matches the underlying
  dataCenters array, --dc still finds a flavour even when its datacentre
  is hidden behind "+N more".
  This verb takes no other filters: the product is fixed at POD,SERVERLESS.

**API:** `GET /v2/catalog/cpus  (include=AVAILABILITY, product=POD,SERVERLESS)`

