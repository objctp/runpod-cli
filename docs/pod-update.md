# rp pod update
Change a pod's configuration in place, restarting it.

```
rp pod update <id> [flags]
```

## Arguments

```
  <id>                           pod id — from `rp pod list`
```

## Options

```
  --name <n>                     rename the pod
  --image <ref>                  Docker image reference
  --container-disk-gb N          ephemeral container disk, GB (minimum 1)
                                 (alias: --container-disk-in-gb)
  --volume-gb N                  resize the host-local persistent volume, GB
                                 (alias: --volume-in-gb)
  --volume-path <path>           mount path (default: /workspace)
                                 (alias: --volume-mount-path)
  --ports <a/b,…>                exposed ports, each as port/protocol
  --env K=V                      environment variable; repeatable; NOT aliased to runpodctl's --env (a single JSON object) — the repeatable K=V shapes differ
  --start-cmd <a,b,…>            arguments passed to the container entrypoint
                                 (alias: --docker-args)
  --registry <id>                registry credential for a private image
                                 (alias: --registry-auth-id)
  --global-networking true|false enable or disable global networking; omit to
                                 leave it unchanged
  --locked true|false            lock the pod against stop and restart; omit
                                 to leave it unchanged
  --json                         print the raw API response
```

## Notes
  This resets a running pod. Anything outside /workspace or a network volume
  is wiped, and the CLI prints a reminder before sending the request.
  At least one flag is required; with none, the command exits with a usage
  error rather than sending an empty PATCH.
  The mount kind is fixed at create. Introducing a kind the pod was not
  created with — persistent on a network pod, or either on a pod created
  without a mount — is rejected by the API.
  A network volume's id is immutable; only its mount path may change.
  --global-networking takes effect on the next start or restart, not live.
  A locked pod cannot be stopped or restarted until it is unlocked.

## Examples

```
# Rename the pod
$ rp pod update pod_abc123 --name renamed

# Grow the container disk and set an env var
$ rp pod update pod_abc123 --container-disk-gb 80 --env HF_TOKEN=xxx
```

**API:** `PATCH /v2/pods/{id}`

