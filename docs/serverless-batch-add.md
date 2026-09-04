# rp serverless batch add
Append requests to a DRAFT batch (beta).

```
rp serverless batch add <endpoint> <batchId> [--input '<json>']… [--input-file <path|->]
```

## Arguments

```
  <endpoint>       endpoint id
  <batchId>        batch id — printed by `batch create`
```

## Options

```
  --input '<json>' one request's input object; repeatable
  --input-file <path|->
                   a JSON array of input objects; `-` reads stdin; items
                   precede --input values in the envelope
```

## Notes
  The API wraps the array as {"requests":[…]} and caps one call at 10 MiB —
  oversized payloads are rejected locally before the POST; split them across
  multiple add calls (each add is a visible billing/progress boundary, so the
  CLI never chunks silently). Only DRAFT batches accept requests.

**API:** `POST /v2/{endpoint_id}/batch/{batch_id}/requests`

