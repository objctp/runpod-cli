# rp ssh-key add
Add a public key from a file, stdin, or generate a fresh pair.

```
rp ssh-key add [<file|>] [--key-file <path>] [--key <pub>] [--name <n>] [--type rsa|ed25519] [--force] [--from-runpodctl]
```

## Arguments

```
  <file|->  public-key file to read; - or no argument reads stdin. When no
            file, --key, --key-file, or --from-runpodctl is given, a new key
            pair is generated and registered instead.
```

## Options

```
  --key-file <path>   read the public key from this file (alias of the positional)
  --key <pub>         register this public-key string directly
  --name <n>          name for a generated key (default: rp-ssh-key)
  --type rsa|ed25519  algorithm for a generated key (default: rsa, 2048-bit)
  --force             overwrite an existing generated key of the same name
                      without prompting
  --from-runpodctl    import every public key found under runpodctl's ssh
                      directory (~/.runpod/ssh); the matching private keys are
                      copied into $RP_CONFIG_HOME/ssh
```

## Notes
  A generated pair is written to $RP_CONFIG_HOME/ssh/<name> (private, 0600)
  and <name>.pub (public, 0644) so it can be reused for pod connections; only
  the public half is sent to Runpod. Generation prompts for confirmation on a
  TTY unless --force is given. Only the first non-blank line of a supplied key
  is registered, and re-adding a key you already hold is a no-op.
  `--from-runpodctl` de-duplicates against the account's existing key set, so
  re-running it is safe: already-registered keys are skipped.
  The write is read-modify-write: the whole set is fetched, appended to, and
  PUT back (the v2 route replaces the entire key set), so two adds racing from
  the same host are serialised behind a lock.

## Examples

```
# Add a public key from a file
$ rp ssh-key add ~/.ssh/id_ed25519.pub

# Pipe a public key straight from ssh-keygen
$ ssh-keygen -y -f ~/.ssh/id_ed25519 | rp ssh-key add -

# Generate a fresh key pair and register it
$ rp ssh-key add

# Migrate runpodctl's keys into rp and register any missing from the account
$ rp ssh-key add --from-runpodctl
```

**API:** `GET then PUT /v2/account/ssh-keys`

