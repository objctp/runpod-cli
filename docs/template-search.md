# rp template search
Find your templates whose name contains a substring.

```
rp template search <name-substring> [--json]
```

## ARGUMENTS

```
  <name-substring>  text to look for; matching is case-insensitive
```

## OPTIONS

```
  --json            print the matching array instead of the table
```

## NOTES
  The match is client-side: every template is fetched and then filtered on
  name, because v2 has no search parameter on GET /v2/templates.
  The columns are the same as `rp template list` — id, name, image and
  serverless.
  A template with no name never matches, and a query that matches nothing
  prints the header row alone.
  This verb does not page: --limit and --cursor belong to
  `rp template list`. Narrow the substring instead.

## EXAMPLES

```
  rp template search pytorch
  rp template search infer --json
```

**API:** `GET /v2/templates`

