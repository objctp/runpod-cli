# rp volume update
Rename a network volume, or grow it.

```
rp volume update <id> [--name <n>] [--size <gb>] [--json]
```

## ARGUMENTS

```
  <id>         network volume id — from `rp volume list`
```

## OPTIONS

```
  --name <n>   rename the volume
  --size <gb>  new capacity in GB; may only grow
  --json       print the raw API response
```

## NOTES
  At least one of --name or --size is required; with neither, the command
  exits with a usage error rather than sending an empty PATCH.
  Capacity only grows. The API rejects a size below the current one and
  there is no shrink path — copy elsewhere and recreate instead.
  name and size are the only fields the API accepts here. The datacentre and
  the storage tier are both fixed at create.
  This verb takes an id, not a name; `rp volume list` prints both.

## EXAMPLES

```
  rp volume update netvol_abc123 --name archive
  rp volume update netvol_abc123 --size 1000
```

**API:** `PATCH /v2/network-volumes/{id}`

