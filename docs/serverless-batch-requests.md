# rp serverless batch requests
List a batch's child requests with per-request status and results (beta).

```
rp serverless batch requests <endpoint> <batchId> [--status completed|failed|in-progress|queued] [--limit N] [--cursor N] [--json]
```

## Arguments

```
  <endpoint>       endpoint id
  <batchId>        batch id
```

## Options

```
  --status <s>     client-side filter (completed|failed|in-progress|queued);
                   --status completed is the results view
  --limit <n>      page size (server-side)
  --cursor <n>     server-side offset for the next page
  --json           print the raw paginated envelope (incl. total/hasMore)
```

## Notes
  Pagination is server-side (offset/limit); each child carries a status and
  either an output or an error message from the handler. A failed child does
  not fail the batch.

**API:** `GET /v2/{endpoint_id}/batch/{batch_id}/requests`

