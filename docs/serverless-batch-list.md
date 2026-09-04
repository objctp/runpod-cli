# rp serverless batch list
List an endpoint's batches, newest first (beta).

```
rp serverless batch list <endpoint> [--json]
```

## Arguments

```
  <endpoint>       endpoint id — from `rp serverless list`
```

## Options

```
  --json           print the raw API response
```

## Notes
  The table shows each batch's id, name, status and request counts (total,
  completed, failed, in flight). A batch that is still processing reports
  FINALIZED — there is no RUNNING or COMPLETED status.

**API:** `GET /v2/{endpoint_id}/batch`

