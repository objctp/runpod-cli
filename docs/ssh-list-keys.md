# rp ssh list-keys
List your registered public keys.
DEPRECATED — use `rp ssh-key list`.

```
rp ssh list-keys [--json]
```

## Options

```
  --json  print the keys as a JSON array of authorized-key lines
```

## Notes
  DEPRECATED: this verb now warns and delegates to `rp ssh-key list`, which is
  the canonical key command — same v2 REST route, same output. Prefer
  `rp ssh-key list` in new scripts. The table shows the key type, its SHA256
  fingerprint, and the first 64 characters of the key itself. Fingerprints are
  computed locally by ssh-keygen; where ssh-keygen is absent the column reads -
  and fingerprint matching stops working. Every key lives in the v2 account key
  set; the CLI splits it into one key per line.

**API:** `GET /v2/account/ssh-keys`

