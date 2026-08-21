# rp ssh
Pod ssh connection line; key management moved to rp ssh-key.
`info` prints the ssh connection line for a running pod. The three key verbs
(list-keys / add-key / remove-key) are DEPRECATED aliases onto the v2 REST
`rp ssh-key` Resource: this file sources commands/ssh-key.sh and calls its
_sshkey_* functions, warning and delegating so the key logic lives in exactly
one place. There is no GraphQL path — both surfaces hit
GET/PUT /v2/account/ssh-keys. Use `rp ssh-key` for keys; `rp ssh` is now just
`info`.

```
rp ssh <verb> [flags]
```

## COMMANDS

- [`rp ssh list-keys`](ssh-list-keys.md) — List your registered public keys.
- [`rp ssh add-key`](ssh-add-key.md) — Add a public key from a file or stdin.
- [`rp ssh remove-key`](ssh-remove-key.md) — Remove a registered public key.
- [`rp ssh info`](ssh-info.md) — Print the ssh connection line for a running pod.
