# How-to: rename a cluster (update only its name)

This is a single-task guide. The reference page (`rp doc cluster update`)
documents the flag and the API route; this page shows the one call you need
and the constraints around it.

Goal: change a cluster's name after it has been created.

## Steps

1. Find the cluster id from `rp cluster list` (the `<id>` column, e.g.
   `cluster_abc123`). The `update` verb takes the cluster **by id only** — it
   does not resolve names:

   ```
   $ rp cluster update cluster_abc123 --name new-name
   ```

   This sends a `PATCH /v2/clusters/cluster_abc123` carrying only
   `{"name": "new-name"}`. On success the CLI prints a confirmation naming
   the cluster id on stderr; nothing is written to stdout.

## Notes

- The cluster is identified by **id only**. `rp cluster update` performs no
  name→id resolution; passing a name reaches the API as `/v2/clusters/<name>`
  and fails.
- `--name` is the **only mutable field**. Compute shape, cluster type, and
  container configuration are fixed at create time and cannot be changed here.
- There is no separate "rename" verb — `rp cluster update` is the rename
  command. Any field other than `--name` is ignored; omitting `--name` errors
  out with the usage hint.
- Because the request touches only the name field, no member pods are
  affected by it.
