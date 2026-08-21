# rp cluster update
Rename a cluster.

```
rp cluster update <id> --name <n>
```

## ARGUMENTS

```
  <id>             cluster id — from `rp cluster list`
```

## OPTIONS

```
  --name <n>       new cluster name (required)
  --json           print the raw API response
```

## NOTES
  Rename is the only mutable field. Compute shape, type, and container config
  are fixed at create and cannot be changed here.

**API:** `PATCH /v2/clusters/{id}`

