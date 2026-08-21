# rp serverless delete
Delete a serverless endpoint permanently.

```
rp serverless delete <id>
```

## ARGUMENTS

```
  <id>             endpoint id — from `rp serverless list`
```

## NOTES
  Deletion is irreversible; any scaled workers are torn down with it.

**API:** `DELETE /v2/serverless/{id}`

