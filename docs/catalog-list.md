# rp catalog list
List public catalog templates (id, name, image, flags).

```
rp catalog list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
```

## Options

```
  --limit N      return at most N templates
  --cursor <c>   offset to resume from; pairs with --limit
  --jq <filter>  jq filter applied to the array
  --json         print the raw API response
```

## Notes
  These are the community catalog templates, not your own `template` Resource
  entries. The v2 catalog surface is list-only, so there is no get/delete here
  — copy a template id into `rp pod create --template-id` or
  `rp serverless create --template-id` to use one.
  `serverless` marks templates built for serverless workers; `public` marks
  templates visible to other Runpod users.

**API:** `GET /v2/catalog/templates`

