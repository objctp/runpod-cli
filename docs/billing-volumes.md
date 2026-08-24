# rp billing volumes
Report network volume spend, optionally for one volume.

```
rp billing volumes [<id>] [--start <rfc3339>] [--end <rfc3339>]
                          [--bucket-size hour|day|week|month|year]
                          [--last-n N] [--json]
```

## Arguments

```
  <id>                                    network volume id; omit for every
                                          volume
```

## Options

```
  --start <rfc3339>                       window start, inclusive
  --end <rfc3339>                         window end, exclusive
  --bucket-size hour|day|week|month|year  size of each record's bucket
  --last-n N                              the last N buckets instead of a
                                          window; minimum 1
  --json                                  print the raw API response
```

## Notes
  <id> is a volume id from `rp volume list`, sent as networkVolumeId. Unlike
  the S3 verbs of `rp volume`, this takes no name and resolves nothing.
  A volume bills for its provisioned capacity whether or not anything mounts
  it, so deleted pods do not end the charge — deleting the volume does.
  --last-n counts back from now in whole buckets. It cannot be combined with
  --start or --end, and its minimum is 1.

## Examples

```
# Spend for network volumes over the last year, monthly
$ rp billing volumes --last-n 12 --bucket-size month
```

**API:** `GET /v2/billing/network-volumes`

