# rp pod delete
Terminate a pod permanently.

```
rp pod delete <id>
```

## Arguments

```
  <id>             pod id — from `rp pod list`
```

## Notes
  Termination is irreversible and is not the same as `rp pod stop`: a stopped
  pod keeps its disks and can be started again, whilst a terminated one is
  gone.
  Host-local persistent storage dies with the pod. An attached network volume
  outlives it and must be removed with `rp volume delete`.

**API:** `DELETE /v2/pods/{id}`

