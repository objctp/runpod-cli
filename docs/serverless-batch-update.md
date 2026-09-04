# rp serverless batch update
Rename a batch (beta).

```
rp serverless batch update <endpoint> <batchId> --name <n>
```

## Arguments

```
  <endpoint>       endpoint id
  <batchId>        batch id
```

## Options

```
  --name <n>       new display name (required)
```

## Notes
  The name is a display label only; batches are always addressed by id.

**API:** `PUT /v2/{endpoint_id}/batch/{batch_id}`

