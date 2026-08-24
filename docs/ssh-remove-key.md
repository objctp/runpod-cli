# rp ssh remove-key
Remove a registered public key.
DEPRECATED — use `rp ssh-key remove`.

```
rp ssh remove-key <fingerprint|key>
```

## Arguments

```
  <fingerprint|key>  SHA256 fingerprint from `rp ssh-key list`, or any
                     substring of the key line
```

## Notes
  DEPRECATED: this verb now warns and delegates to `rp ssh-key remove`, the
  canonical key command (same v2 REST route). Exactly one key must match: a
  fingerprint is compared whole and anything else as a substring, so a fragment
  hitting several keys is rejected rather than removing them all. No match is a
  not-found error and nothing is written. The surviving keys are rewritten as a
  JSON array, so the same read-modify-write race as `rp ssh add-key` applies.
  --json is accepted and ignored.

## Examples

```
# Remove a key by its fingerprint
$ rp ssh-key remove SHA256:2yKPqJ4hTVEnBmvJ5vHJd0LmqUTAqZk0lQbHkbG0kQE

# Remove a key by its comment/email
$ rp ssh-key remove laptop@example.com
```

**API:** `PUT /v2/account/ssh-keys`

