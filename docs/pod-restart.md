# rp pod restart
Restart a running pod.

```
rp pod restart <id>
```

## ARGUMENTS

```
  <id>             pod id — from `rp pod list`
```

## NOTES
  The container is recreated, so anything written outside /workspace or a
  network volume is lost.
  A locked pod refuses to restart.

**API:** `POST /v2/pods/{id}/action  (action: restart)`

