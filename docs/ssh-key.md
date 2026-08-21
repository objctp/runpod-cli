# rp ssh-key
SSH public keys over the API v2 REST plane.
The canonical home for key management: `rp ssh list-keys` / `add-key` /
`remove-key` are aliases that source this file and call the _sshkey_* functions
below, so the key logic exists in exactly one place. The v2 route replaces the
WHOLE key set on PUT, so add/remove are read-modify-write around a lock.

```
rp ssh-key <verb> [flags]
```

## COMMANDS

- [`rp ssh-key list`](ssh-key-list.md) — List your registered public keys (API v2 REST plane).
- [`rp ssh-key add`](ssh-key-add.md) — Add a public key from a file or stdin (API v2 REST plane).
- [`rp ssh-key remove`](ssh-key-remove.md) — Remove a registered public key (API v2 REST plane).
