# rp billing all
Report aggregated spend across every product.

```
rp billing all [--start <rfc3339>] [--end <rfc3339>]
                      [--bucket-size hour|day|week|month|year]
                      [--last-n N] [--json]
```

## OPTIONS

```
  --start <rfc3339>                       window start, inclusive
  --end <rfc3339>                         window end, exclusive
  --bucket-size hour|day|week|month|year  size of each record's bucket
  --last-n N                              the last N buckets instead of a
                                          window; minimum 1
  --json                                  print the raw API response
```

## NOTES
  Each record totals the account across products, so this is the number to
  reconcile against an invoice; the per-product verbs are where a total gets
  broken down.
  The verb takes no id, and a positional argument is accepted and ignored.
  --last-n counts back from now in whole buckets. It cannot be combined with
  --start or --end, and its minimum is 1.

## EXAMPLES

```
  rp billing all --last-n 6 --bucket-size month
```

**API:** `GET /v2/billing`

