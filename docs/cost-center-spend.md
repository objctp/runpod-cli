# rp cost-center spend
Report spend per cost center, rolled up from the billing endpoints.

```
rp cost-center spend [<name>] [--start <rfc3339>] [--end <rfc3339>]
                            [--bucket-size hour|day|week|month|year]
                            [--last-n N] [--json]
```

## Arguments

```
  <name>                                    cost center; omit for every
                                            center plus Uncategorized
```

## Options

```
  --start <rfc3339>                         window start, inclusive
  --end <rfc3339>                           window end, exclusive
  --bucket-size hour|day|week|month|year    size of each billing bucket
  --last-n N                                the last N buckets instead of a
                                            window; minimum 1
  --json                                    print the full per-resource
                                            breakdown as JSON
```

## Notes
  Each bucket's total is the sum of its members' spend, each read from the
  same v2 billing endpoints `rp billing` uses — one call per typed resource.
  An id whose type is unknown (recorded before its resource listable, or
  assigned by hand) is billed against every product; the sum stays correct
  because an id only appears in its own product's report.
  Without <name>, every bucket is reported plus Uncategorized — every
  resource the lists know that is tagged nowhere. The whole-account view
  covers resources that still exist; a deleted resource's history remains
  reachable inside the bucket it was tagged to.
  --last-n is mutually exclusive with --start/--end, exactly as in
  `rp billing`.

## Examples

```
# Per-project spend over the last month, daily
$ rp cost-center spend --last-n 1 --bucket-size month

# One project's spend since July
$ rp cost-center spend rag-pipeline --start 2026-07-01T00:00:00Z

# Full breakdown as JSON
$ rp cost-center spend rag-pipeline --json
```

**API:** `GET /v2/billing/pods, GET /v2/billing/serverless,`

     GET /v2/billing/network-volumes, GET /v2/billing/clusters
