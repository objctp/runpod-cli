# rp billing public-endpoints
Report spend on the public endpoint product.

```
rp billing public-endpoints [--start <rfc3339>] [--end <rfc3339>]
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
  Public endpoints are Runpod's own hosted inference APIs, billed as their
  own product. This is not spend on endpoints you deployed — that is
  `rp billing serverless`.
  The verb takes no id: the API offers no filter for this product, so the
  whole account's history comes back. A positional argument is accepted and
  ignored.
  --last-n counts back from now in whole buckets. It cannot be combined with
  --start or --end, and its minimum is 1.

## EXAMPLES

```
  rp billing public-endpoints --last-n 30 --bucket-size day
```

**API:** `GET /v2/billing/endpoints`

