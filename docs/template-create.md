# rp template create
Create a template from an image and a container config.

```
rp template create --name <n> --image <img> [flags]
```

## OPTIONS

```
  --name <n>                template name (required)
  --image <img>             Docker image reference (required)
  --serverless              build a serverless template rather than a pod one
  --category CPU|NVIDIA|AMD hardware family the template targets
                            (default: NVIDIA)
  --public true|false       publish the template; omit for the API default
                            (false)
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
  --force                   create even when a template of this name exists
```

## NOTES
  --name and --image are both required, and the CLI checks for both before
  sending the request.
  Create is idempotent by name: without --force, a template already carrying
  this name is not recreated — its id is printed and no POST is sent.
  --serverless is a bare flag, so it can only turn the serverless kind on.
  --volume-gb is ignored with a warning when --serverless is set: serverless
  templates reject a volume mount. --volume-path (alias --volume-mount-path)
  sets the volume's mount path and is only meaningful alongside --volume-gb;
  given without --volume-gb it errors, and omitted it defaults to /workspace.
  --public is tri-state: omitting it leaves the key out of the body, so the
  API applies its own default and the template stays private.
  --category is checked locally against CPU|NVIDIA|AMD before the request.
  --docker-cmd is joined with spaces into v2's single `args` string; v1 took
  an array.
  The new id is printed on stdout and the confirmation goes to stderr, so
  `id=$(rp template create …)` captures just the id.

## EXAMPLES

```
  rp template create --name torch-base --image runpod/pytorch:2.2.0 \
    --container-disk-gb 20 --env HF_HOME=/workspace/hf
  rp template create --name infer --image myrepo/infer:1 --serverless \
    --registry reg_abc123
```

**API:** `POST /v2/templates`

