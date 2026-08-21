# rp ssh-key
SSH public keys over the API v2 REST plane.
The legacy `rp ssh list-keys` / `add-key` / `remove-key` verbs still talk to
the GraphQL plane (no v2 user-settings path existed when they were written).
These `rp ssh-key` verbs are the v2 REST equivalents, backed by GET/PUT
/v2/account/ssh-keys, living alongside the GraphQL ones. The v2 route replaces
the WHOLE key set on PUT, so add/remove are read-modify-write around a lock.

```
rp ssh-key <verb> [flags]
```

## COMMANDS

- [`rp ssh-key list`](ssh-key-list.md) — List your registered public keys (API v2 REST plane).
- [`rp ssh-key add`](ssh-key-add.md) — Add a public key from a file or stdin (API v2 REST plane).
- [`rp ssh-key remove`](ssh-key-remove.md) — Remove a registered public key (API v2 REST plane).
