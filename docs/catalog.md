# rp catalog
Catalog templates: browse the public template library.
Distinct from the `template` Resource (your own private/serverless
templates). Catalog templates are read-only here — the v2 surface exposes
GET /v2/catalog/templates only, so there is no create/get-by-id/delete. Use
`rp catalog list` to browse and copy an id into `rp pod create --template-id`
or `rp serverless create --template-id`.

```
rp catalog <verb> [flags]
```

## COMMANDS

- [`rp catalog list`](catalog-list.md) — List public catalog templates (id, name, image, flags).
