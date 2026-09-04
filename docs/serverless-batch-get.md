# rp serverless batch get
Show a batch's progress summary (beta).

```
rp serverless batch get <endpoint> <batchId> [--wait] [--interval <s>] [--timeout <s>] [--json]
```

## Arguments

```
  <endpoint>       endpoint id
  <batchId>        batch id
```

## Options

```
  --wait           poll until the counts reconcile (completed + failed =
                   total) or the batch reaches a terminal state
  --interval <s>   seconds between polls (default 5)
  --timeout <s>    cap the wait (default: none — batches are multi-hour by
                   design; Ctrl-C or this flag ends the wait)
  --json           print the raw API response
```

## Notes
  The API has no RUNNING/COMPLETED status: progress is the counts. With
  --wait, headlines print to stderr only when the done-count changes, so
  --json stdout and pipes stay clean. Exit code: 0 on completion regardless
  of how many child requests failed (failures are data — see `batch
  requests`); 1 when the batch itself reaches FAILED or CANCELLED; non-zero
  when --timeout expires.

## Examples

```
# Wait for a batch to finish, checking every 30s
$ rp serverless batch get end_abc b_01j9abc --wait --interval 30
```

**API:** `GET /v2/{endpoint_id}/batch/{batch_id}`

