# rp volume ls
List the objects stored on a network volume.

```
rp volume ls <name> [--path <remote-path>]
```

## Arguments

```
  <name>                network volume name — from `rp volume list`
```

## Options

```
  --path <remote-path>  key prefix to list; omit for the volume root
```

## Notes
  This is `aws s3 ls` against the volume's S3 endpoint, so it needs the aws
  CLI and the RUNPOD_S3_ACCESS_KEY / RUNPOD_S3_SECRET_KEY pair. The listing
  is printed verbatim, which is why there is no --json.
  The listing is one level deep: sub-prefixes show as PRE entries rather
  than being expanded. Pass --path to descend into one.
  Unlike `rp volume sync`, this does not check that the datacentre supports
  the S3 API beforehand, so a volume outside those datacentres fails inside
  aws rather than with a clear message.

## Examples

```
# List everything stored on the volume
$ rp volume ls models

# List one model's subtree
$ rp volume ls models --path models/meta-llama
```

**API:** `GET /v2/network-volumes/{id}, then `aws s3 ls` on s3api-<dc>.runpod.io`

