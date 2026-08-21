# rp ssh
SSH public keys, and the ssh line for a running pod.
Your keys live on your account as a set the v2 REST route serves as a JSON
array (`{keys:[...]}`); the three key verbs read and rewrite that set over
`GET`/`PUT /account/ssh-keys` — the same v2 path `rp ssh-key` uses. `info` is
the exception: it reads a pod's runtime ports over REST and prints the command
that reaches it.

```
rp ssh <verb> [flags]
```

## COMMANDS

- [`rp ssh list-keys`](ssh-list-keys.md) — List your registered public keys.
- [`rp ssh add-key`](ssh-add-key.md) — Add a public key from a file or stdin.
- [`rp ssh remove-key`](ssh-remove-key.md) — Remove a registered public key.
- [`rp ssh info`](ssh-info.md) — Print the ssh connection line for a running pod.
