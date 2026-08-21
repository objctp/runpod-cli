# rp volume
Network volume lifecycle, model sync, and GPU stock lookup.
A network volume is durable storage pinned to one datacentre, mountable by
pods and serverless endpoints and outliving all of them. The CRUD verbs take
a volume id; the data-plane verbs (sync, ls, gpus) take a name and resolve it
for you. File transfer rides the S3-compatible API, which only some
datacentres expose.

```
rp volume <verb> [flags]
```

## COMMANDS

- [`rp volume list`](volume-list.md) — List your network volumes as a table: id, name, size, dataCenter.
- [`rp volume get`](volume-get.md) — Show one network volume's full record.
- [`rp volume create`](volume-create.md) — Create a network volume in a datacentre.
- [`rp volume update`](volume-update.md) — Rename a network volume, or grow it.
- [`rp volume delete`](volume-delete.md) — Delete a network volume permanently.
- [`rp volume sync`](volume-sync.md) — Upload a local directory or Hugging Face models to a volume.
- [`rp volume ls`](volume-ls.md) — List the objects stored on a network volume.
- [`rp volume gpus`](volume-gpus.md) — List GPU types in stock, with the volume's datacentre noted.
