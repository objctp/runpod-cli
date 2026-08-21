# rp billing clusters
Report instant cluster spend, optionally for one cluster.

```
rp billing clusters [<id>] [--start <rfc3339>] [--end <rfc3339>]
                           [--bucket-size hour|day|week|month|year]
                           [--last-n N] [--json]
```

## ARGUMENTS

```
  <id>                                    cluster id; omit for every cluster
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
  Instant clusters are multi-node GPU deployments. The CLI has no verb that
  creates or lists them, so the id has to come from the console or from a
  record in an earlier report.
  <id> is sent as clusterId.
  --last-n counts back from now in whole buckets. It cannot be combined with
  --start or --end, and its minimum is 1.

**API:** `GET /v2/billing/clusters`

