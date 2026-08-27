# rp stock cpus
List reservable CPU instances with price and availability.

```
rp stock cpus [--dc <id>] [--vcpu N] [--product POD|SERVERLESS|CLUSTER] [--compact] [--json]
```

## Options

```
  --dc <id>       keep only flavours stocked in this datacentre (case-insensitive)
  --vcpu N        keep only instances of N vCPUs (a power of two, minimum 2)
  --product <p>   POD, SERVERLESS or CLUSTER; show only that tier's price column
                  and drop flavours not offered on it (default: POD,SERVERLESS,
                  both columns)
  --compact       show one row per flavour (the old vcpu-range table) instead of
                  one row per power-of-two size
  --json          print the raw API response (the flavour objects, not expanded)
```

## Notes
  By default this verb EXPANDS each flavour into one row per deployable size:
  every power-of-two vCPU count inside the flavour's valid range (2, 4, 8,
  16, 32, …). That is exactly the set `rp pod create --cpu-flavor <ID>
  --vcpu <n>` accepts, so each row is a real instance you can reserve.
  FLAVOUR is the flavour id `rp pod create --cpu-flavor` takes; VCPU and
  RAM_GB are that instance's size and total RAM (= VCPU × RAM_GB_VCPU).
  SECURE_PRICE and SERVERLESS_PRICE are the hourly rates for that instance
  size: the total (VCPU × per-vCPU rate) with the per-vCPU rate in
  parentheses. With --product the OTHER tier's column is dropped entirely, and
  any flavour not offered on that product (e.g. Memory-Optimized on
  SERVERLESS, whose serverless price is 0) is omitted from the table. A dash
  in the remaining price column means that tier is not offered.
  STOCK is shown only with --dc: it then reflects that datacentre's own
  availability (region-accurate). Without --dc the column is hidden, since the
  flavour-level value is only a global "available somewhere" aggregate.
  --vcpu N narrows the expanded rows to one size (validated: power of two,
  >= 2); --compact collapses back to one row per flavour (VCPU shown as a
  min-max range, RAM_GB_VCPU and the tier price as per-vCPU values).
  DATACENTERS lists every datacentre the flavour is stocked in, but the
  table column is truncated to the first two ids followed by "+N more"
  (e.g. "EU-CZ-1, EU-NL-1 +12 more") to keep the row readable; the full
  list is always in --json. Because filtering matches the underlying
  dataCenters array, --dc still finds a flavour even when its datacentre
  is hidden behind "+N more".
  --dc and --product apply to BOTH the table and --json so the two views
  always show the same flavours.

**API:** `GET /v2/catalog/cpus  (include=AVAILABILITY, product=<selected>)`

