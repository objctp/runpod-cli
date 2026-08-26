# rp ssh-key remove
Remove a registered public key.

```
rp ssh-key remove <fingerprint|key>
```

## Arguments

```
  <fingerprint|key>  SHA256 fingerprint from `rp ssh-key list`, or any
                     substring of the key line
```

## Notes
  Exactly one key must match. A fingerprint is compared whole and anything
  else as a substring, so a fragment that hits several keys is rejected rather
  than removing them all.
  The surviving keys are written back via a full-set PUT.

## Examples

```
# Remove a key by its fingerprint
$ rp ssh-key remove SHA256:2yKPqJ4hTVEnBmvJ5vHJd0LmqUTAqZk0lQbHkbG0kQE

# Remove a key by its comment/email
$ rp ssh-key remove laptop@example.com
```

**API:** `GET then PUT /v2/account/ssh-keys`

