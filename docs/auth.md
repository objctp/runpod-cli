# rp auth
Manage Runpod API credentials in a stable per-user store.
This store survives any install method — including an npm global install
whose files live inside node_modules and are wiped on every `npm upgrade`.
Modeled on gh's multi-account support (v2.40.0): one key per account,
exactly one "active" account used for API calls, switchable with
`rp auth switch`.
Layout under $RP_CONFIG_HOME:
  credentials.d/<name>   one account: RUNPOD_API_KEY (+ optional S3 keys)
  active                 a file containing the name of the active account
There is no OAuth/browser login — Runpod is API-key only, so `login` just
captures and stores the key you copy from console > Settings > API Keys.

```
rp auth <verb> [flags]
```

## Commands

- [`rp auth use`](auth-use.md) — Alias for `rp auth switch <name>` — change the active account.
- [`rp auth login`](auth-login.md) — Store a Runpod API key as an account (additive — does not replace others).
- [`rp auth logout`](auth-logout.md) — Remove an account (mirrors gh auth logout).
- [`rp auth switch`](auth-switch.md) — Change the active account — the one used for all API calls.
- [`rp auth list`](auth-list.md) — Show stored accounts, marking the active one.
- [`rp auth status`](auth-status.md) — Show the active account and whether an API key is configured.
