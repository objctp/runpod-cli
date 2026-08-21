# rp ssh add-key
Add a public key from a file or stdin.

```
rp ssh add-key <file|->
```

## ARGUMENTS

```
  <file|->  public-key file to read; - or no argument reads stdin
```

## NOTES
  Only the first non-blank line of the input is registered, so pointing this
  at an authorized_keys file with several keys adds just the first.
  Re-adding a key you already hold is a no-op: the CLI says so and writes
  nothing.
  The write is read-modify-write over the v2 key set — the whole set is
  fetched, appended to, and sent back as a JSON array — so two adds racing
  from different sessions can lose one of the keys.
  --json is accepted and ignored: the outcome is a status line on stderr.

## EXAMPLES

```
  rp ssh add-key ~/.ssh/id_ed25519.pub
  ssh-keygen -y -f ~/.ssh/id_ed25519 | rp ssh add-key -
```

**API:** `PUT /v2/account/ssh-keys`

