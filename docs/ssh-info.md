# rp ssh info
Print the ssh connection line for a running pod.

```
rp ssh info <pod-id> [--json]
```

## ARGUMENTS

```
  <pod-id>  pod id — from `rp pod list`
```

## OPTIONS

```
  --json    print the raw pod record the line was derived from
```

## NOTES
  This is the one verb here that never touches the key set: it reads the pod
  over REST API v2 and formats what it finds, so it keeps working even where
  the key verbs would not. The line comes from the first runtime port labelled
  ssh, or failing that the first TCP port, printed as `ssh root@<ip> -p <port>`.
  A stopped pod has no runtime and so no connection line — the command says as
  much rather than failing. Start the pod and ask again. A running pod exposing
  no ssh or TCP port prints its runtime ports instead. Registering a key with
  `rp ssh add-key` is what makes the address usable; this verb only reports it.

**API:** `GET /v2/pods/{id}`

