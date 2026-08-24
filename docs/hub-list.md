# rp hub list
Browse all Hub listings, filtered and ordered.

```
rp hub list [--category <c>] [--order-by <field>] [--order-dir ASC|DESC]
                    [--owner <owner>] [--limit <n>] [--offset <n>] [--type <t>] [--json]
```

## Options

```
  --category <c>     filter by category
  --order-by <field> sort field (e.g. createdAt)
  --order-dir <dir>  ASC or DESC
  --owner <owner>    restrict to a repository owner
  --limit <n>        max rows to return
  --offset <n>       rows to skip (paging)
  --type POD|SERVERLESS  the API has no type arg, so this filters the result
                     set client-side after the query (case-insensitive)
  --json             print the raw listings array
```

## Notes
  The table shows the listing id, title, owner and type — the same shape as
  `rp hub search`. That id is what `rp hub get` and `rp serverless create
  --hub-id` take.
  Filters map to the GraphQL ListingsInput args; `--type` is the only flag
  applied after the response returns, because the API offers no type filter.

**API:** `GraphQL listings(input: {category,orderBy,orderDirection,owner,limit,offset})  (NO-V2-EQUIVALENT)`

