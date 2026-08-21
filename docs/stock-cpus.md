# rp stock cpus
List CPU flavours with price and availability.

```
rp stock cpus [--json]
```

## OPTIONS

```
  --json  print the raw API response
```

## NOTES
  The ID column is the value `rp pod create --cpu-flavor` takes.
  VCPU is the flavour's valid vcpuCount range; --vcpu must be a power of two
  inside it.
  RAM_GB_VCPU is the RAM allotted per vCPU and SECURE_PRICE_VCPU the
  secure-cloud hourly rate per vCPU, so both scale with the vCPU count you
  ask for.
  This verb takes no filters: the product is fixed at POD,SERVERLESS.

**API:** `GET /v2/catalog/cpus  (include=AVAILABILITY, product=POD,SERVERLESS)`

