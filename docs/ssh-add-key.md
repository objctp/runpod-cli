# rp ssh add-key
Add a public key from a file or stdin.
DEPRECATED — use `rp ssh-key add`.

```
rp ssh add-key <file|->
```

## Arguments

```
  <file|->  public-key file to read; - or no argument reads stdin
```

## Notes
  DEPRECATED: this verb now warns and delegates to `rp ssh-key add`, the
  canonical key command (same v2 REST route). Only the first non-blank line of
  the input is registered, so pointing this at an authorized_keys file with
  several keys adds just the first. Re-adding a key you already hold is a no-op.
  The write is read-modify-write over the v2 key set — the whole set is fetched,
  appended to, and sent back as a JSON array — so two adds racing from different
  sessions are serialised behind a lock. --json is accepted and ignored: the
  outcome is a status line on stderr.

## Examples

```
# Add a public key from a file
$ rp ssh-key add ~/.ssh/id_ed25519.pub

# Pipe a public key straight from ssh-keygen
$ ssh-keygen -y -f ~/.ssh/id_ed25519 | rp ssh-key add -
```

**API:** `PUT /v2/account/ssh-keys`

