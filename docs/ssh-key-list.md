# rp ssh-key list
List your registered public keys (API v2 REST plane).

```
rp ssh-key list [--json]
```

## Options

```
  --json  print the keys as a JSON array of authorized-key lines
```

## Notes
  This is the canonical key command; `rp ssh list-keys` is a deprecated
  shim that warns and delegates here (same v2 REST route). The table shows
  the key type, its SHA256 fingerprint, and the first 64 characters of the
  key itself.

**API:** `GET /v2/account/ssh-keys`

