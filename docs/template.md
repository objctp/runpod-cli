# rp template
Reusable container configuration for pods and endpoints.
A template is a saved container config — image, entrypoint arguments, ports,
environment, disk — that `rp pod create --template` and the serverless create
paths spread as their defaults. Each one is either a pod template or a
serverless template, and the serverless kind takes no persistent volume.
Templates are private until you publish one with --public true.

```
rp template <verb> [flags]
```

## Commands

- [`rp template list`](template-list.md) — List your templates as a table: id, name, image, serverless.
- [`rp template get`](template-get.md) — Show one template's full record, including its container config.
- [`rp template create`](template-create.md) — Create a template from an image and a container config.
- [`rp template update`](template-update.md) — Change a template's fields in place.
- [`rp template search`](template-search.md) — Find your templates whose name contains a substring.
- [`rp template delete`](template-delete.md) — Delete a template permanently.
