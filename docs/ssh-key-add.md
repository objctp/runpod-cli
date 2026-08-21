# rp ssh-key add
Add a public key from a file or stdin (API v2 REST plane).

```
rp ssh-key add <file|->
```

## ARGUMENTS

```
  <file|->  public-key file to read; - or no argument reads stdin
```

## NOTES
  Only the first non-blank line of the input is registered. Re-adding a key
  you already hold is a no-op.
  The write is read-modify-write: the whole set is fetched, appended to, and
  PUT back (the v2 route replaces the entire key set), so two adds racing from
  the same host are serialised behind a lock.

## EXAMPLES

```
  rp ssh-key add ~/.ssh/id_ed25519.pub
  ssh-keygen -y -f ~/.ssh/id_ed25519 | rp ssh-key add -
```

**API:** `GET then PUT /v2/account/ssh-keys`

