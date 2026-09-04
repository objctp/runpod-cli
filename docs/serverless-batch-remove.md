# rp serverless batch remove
Remove one request from a DRAFT batch (beta).

```
rp serverless batch remove <endpoint> <batchId> <requestId>
```

## Arguments

```
  <endpoint>       endpoint id
  <batchId>        batch id
  <requestId>      child request id — from `batch requests`
```

## Notes
  Only DRAFT batches accept removals; after finalize the request set is
  locked.

**API:** `DELETE /v2/{endpoint_id}/batch/{batch_id}/requests/{request_id}`

