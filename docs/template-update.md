# rp template update
Change a template's fields in place.

```
rp template update <id> [flags]
```

## Arguments

```
  <id>                      template id — from `rp template list`
```

## Options

```
  --name <n>                rename the template
  --image <img>             Docker image reference
  --serverless              mark the template as a serverless template
  --category CPU|NVIDIA|AMD hardware family the template targets
  --public true|false       publish or unpublish; omit to leave it unchanged
  --docker-cmd <a,b,…>      arguments passed to the container entrypoint
                            (alias: --docker-start-cmd)
  --env K=V                 environment variable; repeatable; NOT aliased to runpodctl's --env (a single JSON object) — the repeatable K=V shapes differ
  --ports <a/b,…>           exposed ports, each as port/protocol
  --container-disk-gb N     ephemeral container disk, GB (alias: --container-disk-in-gb)
  --volume-gb N             persistent volume size, GB (alias: --volume-in-gb)
  --volume-path <path>      mount path for the persistent volume (requires
                            --volume-gb; alias: --volume-mount-path); defaults
                            to /workspace
  --registry <id>           registry credential for a private image
                            (alias: --registry-auth-id)
  --json                    print the raw API response
```

## Notes
  At least one flag is required; with none, the command exits with a usage
  error rather than sending an empty PATCH.
  Only the flags you pass are sent, so every unmentioned field keeps its
  value. --env is the trap: the pairs you give replace the template's whole
  env map rather than merging into it.
  --serverless is a bare flag, so update can promote a pod template to a
  serverless one but cannot demote it again.
  --volume-gb is ignored with a warning alongside --serverless, exactly as on
  create.
  --category is sent only when given: the NVIDIA default is create-side.
  Pods and endpoints already built from the template are untouched — they
  copied its container config at create time and never re-read it.

## Examples

```
# Make a template public
$ rp template update tmpl_abc123 --public true

# Repoint a template at a new image and registry
$ rp template update tmpl_abc123 --image myrepo/infer:2 --registry reg_xyz
```

**API:** `PATCH /v2/templates/{id}`

