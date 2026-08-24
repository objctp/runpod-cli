# rp volume delete
Delete a network volume permanently.

```
rp volume delete <id>
```

## Arguments

```
  <id>  network volume id — from `rp volume list`
```

## Notes
  Deletion is irreversible and takes the volume's contents with it. There is
  no stop-and-keep state as there is for a pod.
  A volume still mounted by a pod cannot be deleted. Terminate the pod, or
  recreate it without the mount, first.
  The command prints a confirmation line and nothing else: the response body
  is discarded, so there is no --json output here.

**API:** `DELETE /v2/network-volumes/{id}`

