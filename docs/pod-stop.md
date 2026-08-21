# rp pod stop
Stop a running pod, keeping its disks.

```
rp pod stop <id>
```

## ARGUMENTS

```
  <id>             pod id — from `rp pod list`
```

## NOTES
  A stopped pod still bills for its storage, only the GPU or CPU charge
  ceases. Use `rp pod delete` to stop paying entirely.
  A locked pod refuses to stop; unlock it with
  `rp pod update <id> --locked false`.

**API:** `POST /v2/pods/{id}/action  (action: stop)`

