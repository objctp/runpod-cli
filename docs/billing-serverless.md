# rp billing serverless
Report serverless spend, optionally for one endpoint.

```
rp billing serverless [<id>] [--start <rfc3339>] [--end <rfc3339>]
                             [--bucket-size hour|day|week|month|year]
                             [--last-n N] [--json]
```

## ARGUMENTS

```
  <id>                                    serverless endpoint id; omit for
                                          every endpoint
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
  This is spend on your own serverless endpoints. Runpod's hosted public
  endpoint product is billed separately, under
  `rp billing public-endpoints`.
  <id> is an endpoint id from `rp serverless list`, sent as serverlessId.
  --last-n counts back from now in whole buckets. It cannot be combined with
  --start or --end, and its minimum is 1.
  --bucket-size takes hour, day, week, month or year.

## EXAMPLES

```
  rp billing serverless --last-n 24 --bucket-size hour
  rp billing serverless ep_xyz789 --bucket-size day --json
```

**API:** `GET /v2/billing/serverless`

