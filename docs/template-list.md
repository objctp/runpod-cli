# rp template list
List your templates as a table: id, name, image, serverless.

```
rp template list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## OPTIONS

```
  --limit N        return at most N templates
  --cursor <c>     offset to resume from; pairs with --limit
  --jq <filter>    jq filter applied to the array
  --json           print the raw API response
```

## NOTES
  serverless marks the kind: true for a serverless template, false for a pod
  template.
  Category and visibility have no column here; read them with
  `rp template get`.
  Paging is client-side: the whole list is fetched, then sliced. When output
  is truncated the next cursor is printed to stderr, leaving stdout clean.

**API:** `GET /v2/templates`

