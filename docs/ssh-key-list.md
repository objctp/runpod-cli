# rp ssh-key list
List your registered public keys (API v2 REST plane).

```
rp ssh-key list [--json]
```

## OPTIONS

```
  --json  print the keys as a JSON array of authorized-key lines
```

## NOTES
  This is the v2 REST equivalent of `rp ssh list-keys` (which still uses
  GraphQL). The table shows the key type, its SHA256 fingerprint, and the
  first 64 characters of the key itself.

**API:** `GET /v2/account/ssh-keys`

