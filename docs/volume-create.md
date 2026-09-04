# rp volume create
Create a network volume in a datacentre.

```
rp volume create --name <n> --size <gb> --dc <id>
                        [--type STANDARD|HIGH_PERFORMANCE] [--force]
```

## Options

```
  --name <n>                        volume name (required)
  --size <gb>                       capacity in GB, 10–4096 (required)
  --dc <id>                         datacentre id (required) — see
                                    `rp stock dc` (alias: --data-center-ids)
  --type STANDARD|HIGH_PERFORMANCE  storage tier (default: STANDARD)
  --force                           create even when the name is taken
```

## Notes
  Creation is idempotent by name: where a volume of that name already
  exists, the CLI prints its id and skips the POST. --force sends the
  request regardless, which is how you end up with two volumes sharing a
  name.
  --dc fixes the volume's home. It cannot be moved afterwards, and a pod or
  endpoint that mounts it must be placed in the same datacentre.
  Only some datacentres expose the S3 API. Creating in one that does not is
  allowed but prints a warning, because `rp volume sync` and `rp volume ls`
  will not work there. `rp stock dc` marks the ones that do.
  Likewise, only some datacentres list the HIGH_PERFORMANCE tier. Creating
  with --type HIGH_PERFORMANCE in one that does not is allowed but prints a
  warning, because the request may fail; `rp stock dc --volume-type
  HIGH_PERFORMANCE` marks the ones that do. When the catalog is unreachable
  the check stays silent — the API remains the authority on capability.
  --type is matched case-insensitively and checked locally; anything other
  than STANDARD or HIGH_PERFORMANCE is a usage error. The tier is immutable,
  so `rp volume update` cannot change it later.
  --size is not range-checked here. The API enforces 10–4096 GB and returns
  its own error outside that range.
  The new id is printed on stdout and the confirmation on stderr, so
  `id=$(rp volume create …)` captures just the id.

## Examples

```
# Create a 500 GB volume in the EU-RO-1 datacentre
$ rp volume create --name models --size 500 --dc EU-RO-1

# Create a high-performance volume in Kansas
$ rp volume create --name fast --size 100 --dc US-KS-2 \
    --type HIGH_PERFORMANCE
```

**API:** `POST /v2/network-volumes`

