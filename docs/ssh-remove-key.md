# rp ssh remove-key
Remove a registered public key.

```
rp ssh remove-key <fingerprint|key>
```

## ARGUMENTS

```
  <fingerprint|key>  SHA256 fingerprint from `rp ssh list-keys`, or any
                     substring of the key line
```

## NOTES
  Exactly one key must match. A fingerprint is compared whole and anything
  else as a substring, so a fragment that hits several keys is rejected
  rather than removing them all — pass a longer fingerprint or key fragment.
  No match at all is a not-found error and nothing is written.
  The surviving keys are rewritten as a JSON array, so the same
  read-modify-write race as `rp ssh add-key` applies.
  --json is accepted and ignored: the outcome is a status line on stderr.

## EXAMPLES

```
  rp ssh remove-key SHA256:2yKPqJ4hTVEnBmvJ5vHJd0LmqUTAqZk0lQbHkbG0kQE
  rp ssh remove-key laptop@example.com
```

**API:** `PUT /v2/account/ssh-keys`

