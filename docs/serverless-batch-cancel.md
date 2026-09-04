# rp serverless batch cancel
Cancel a batch (beta).

```
rp serverless batch cancel <endpoint> <batchId>
```

## Arguments

```
  <endpoint>       endpoint id
  <batchId>        batch id
```

## Notes
  Queued requests are cancelled immediately and are not billed; in-flight
  requests finish and bill normally. The batch reaches CANCELLED once the
  in-flight work has drained. No confirmation prompt (house style).

**API:** `POST /v2/{endpoint_id}/batch/{batch_id}/cancel`

