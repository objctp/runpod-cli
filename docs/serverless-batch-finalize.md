# rp serverless batch finalize
Lock a DRAFT batch and make it eligible for execution (beta).

```
rp serverless batch finalize <endpoint> <batchId>
```

## Arguments

```
  <endpoint>       endpoint id
  <batchId>        batch id
```

## Notes
  Finalize is the only door to execution — a DRAFT batch never processes.
  After it, requests can no longer be added or removed; the batch stays
  FINALIZED while it works.

**API:** `POST /v2/{endpoint_id}/batch/{batch_id}/finalize`

