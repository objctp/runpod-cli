# rp ssh info
Print the ssh connection line for a running pod.

```
rp ssh info <pod-id> [--json] [--user <u>]
```

## Arguments

```
  <pod-id>  pod id — from `rp pod list`
```

## Options

```
  --json    print the raw pod record the line was derived from
  --user <u>  remote login user in the connection line (default: root)
```

## Notes
  This is the one verb here that never touches the key set: it reads the pod
  over REST API v2 and formats what it finds, so it keeps working even where
  the key verbs would not. The line comes from the first runtime port whose
  type is ssh or tcp, in the order the API returns them. The login user
  defaults to `root`
  (Runpod official images run as root), but images that run as a non-root user
  need `--user` set to match, otherwise the printed `ssh` line fails with a
  permission error. The --user value is not validated against the pod — the CLI
  has no API field for a container's default user — so pass the user the image
  actually starts as. A stopped pod has no runtime and so no connection line —
  the command says as much rather than failing. Start the pod and ask again. A
  running pod exposing no ssh or TCP port prints its runtime ports instead.
  Registering a key with `rp ssh-key add` is what makes the address usable;
  this verb only reports it.

**API:** `GET /v2/pods/{id}`

