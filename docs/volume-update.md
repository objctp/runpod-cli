# rp volume update
Rename a network volume, or grow it.

```
rp volume update <id> [--name <n>] [--size <gb>] [--json]
```

## Arguments

```
  <id>         network volume id — from `rp volume list`
```

## Options

```
  --name <n>   rename the volume
  --size <gb>  new capacity in GB; may only grow
  --json       print the raw API response
```

## Notes
  At least one of --name or --size is required; with neither, the command
  exits with a usage error rather than sending an empty PATCH.
  Capacity only grows. The API rejects a size below the current one and
  there is no shrink path — copy elsewhere and recreate instead.
  name and size are the only fields the API accepts here. The datacentre and
  the storage tier are both fixed at create.
  This verb takes an id, not a name; `rp volume list` prints both.

## Examples

```
# Rename the volume
$ rp volume update netvol_abc123 --name archive

# Grow the volume to 1000 GB
$ rp volume update netvol_abc123 --size 1000
```

**API:** `PATCH /v2/network-volumes/{id}`

