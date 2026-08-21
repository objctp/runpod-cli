# rp ssh list-keys
List your registered public keys.

```
rp ssh list-keys [--json]
```

## OPTIONS

```
  --json  print the keys as a JSON array of authorized-key lines
```

## NOTES
  The table shows the key type, its SHA256 fingerprint, and the first 64
  characters of the key itself.
  Fingerprints are computed locally by ssh-keygen. Where ssh-keygen is not
  installed the column reads - and matching by fingerprint stops working.
  Every key lives in the v2 account key set; the CLI splits it into one
  key per line.

**API:** `GET /v2/account/ssh-keys`

