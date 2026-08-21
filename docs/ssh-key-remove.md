# rp ssh-key remove
Remove a registered public key (API v2 REST plane).

```
rp ssh-key remove <fingerprint|key>
```

## ARGUMENTS

```
  <fingerprint|key>  SHA256 fingerprint from `rp ssh-key list`, or any
                     substring of the key line
```

## NOTES
  Exactly one key must match. A fingerprint is compared whole and anything
  else as a substring, so a fragment that hits several keys is rejected rather
  than removing them all.
  The surviving keys are written back via a full-set PUT.

## EXAMPLES

```
  rp ssh-key remove SHA256:2yKPqJ4hTVEnBmvJ5vHJd0LmqUTAqZk0lQbHkbG0kQE
  rp ssh-key remove laptop@example.com
```

**API:** `GET then PUT /v2/account/ssh-keys`

