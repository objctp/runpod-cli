# rp pod start
Start a stopped pod.

```
rp pod start <id>
```

## ARGUMENTS

```
  <id>             pod id — from `rp pod list`
```

## NOTES
  Starting is asynchronous: the command returns once the transition is
  accepted, not once the container is RUNNING. Poll with `rp pod get <id>`.
  A start can fail later if the pod's GPU type is out of stock in its
  datacentre.

**API:** `POST /v2/pods/{id}/action  (action: start)`

