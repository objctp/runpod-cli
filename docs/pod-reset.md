# rp pod reset
Deprecated: alias for `restart` — v2 removed the reset action.

```
rp pod reset <id>
```

## Notes
  v2's action enum is start, stop, restart and terminate; there is no reset.
  The verb is kept so existing scripts keep working: it warns and performs a
  restart. Use `rp pod restart` instead.

**API:** `POST /v2/pods/{id}/action  (action: restart)`

