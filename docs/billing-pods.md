# rp billing pods
Report pod spend, optionally for one pod.

```
rp billing pods [<id>] [--start <rfc3339>] [--end <rfc3339>]
                       [--bucket-size hour|day|week|month|year]
                       [--last-n N] [--json]
```

## ARGUMENTS

```
  <id>                                    pod id; omit for every pod
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
  The response is v2's time-bucketed envelope — a records array plus a
  metadata object — printed whole in both output modes.
  Terminated pods still appear. This is billing history, not an inventory of
  what is running now.
  --last-n counts back from now in whole buckets. It cannot be combined with
  --start or --end, and its minimum is 1.
  --bucket-size takes hour, day, week, month or year; anything else is a
  usage error raised before the request goes out.
  Omitting all four window flags returns the account's whole pod history,
  which is slow and noisy on a long-lived account.

## EXAMPLES

```
  rp billing pods --last-n 7 --bucket-size day
  rp billing pods pod_abc123 --start 2026-07-01T00:00:00Z
```

**API:** `GET /v2/billing/pods`

