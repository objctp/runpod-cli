# How-to: manage multiple RunPod accounts and switch between them per command

This is a worked task that spans several `rp auth` sub-commands plus one
per-call override route. The reference pages (`rp doc auth login`, `rp doc auth
switch`, `rp doc auth status`) document the individual flags; this page shows
the account model composed into daily use.

Goal: keep several RunPod API accounts in one store, make global calls under
the active one, and override the account for a single command without
disturbing the active selection.

## The account model

`rp` keeps a per-user credential store under `$RP_CONFIG_HOME` (defaults to
`${XDG_CONFIG_HOME:-$HOME/.config}/rp`). Each account is one file under
`credentials.d/<name>` holding the API key (and optional S3 keys); a single
`active` pointer names the account used for all API calls. Exactly one account
is active at a time. There is no OAuth — Runpod is API-key only, so `login`
just captures the key you copy from console > Settings > API Keys.

## Steps

1. Add accounts as you need them. `login` is additive and marks the new
   account active:

   ```
   $ rp auth login --name work --api-key <key>
   $ rp auth login --name personal --api-key <key>
   ```

   You can import an existing runpodctl install instead of pasting a key
   (interactive `login` also offers this, then prompts for the key with
   input hidden; with no flags at a pipe it reads the key from stdin):

   ```
   $ rp auth login --name old --from-runpodctl
   ```

2. Inspect and switch:

   ```
   $ rp auth list          # one line per account, active marked
   $ rp auth switch work   # change the active account (alias: rp auth use work)
   $ rp auth status        # active account + where the key came from
   ```

   `rp auth status` reports the effective source of each key — an exported
   environment variable, an account file, or the user/install `.env` — so you
   can see which one is actually in force.

3. Override a single command without switching. Every `rp` command accepts a
   global `--account <name>` flag (or the `RP_ACCOUNT` env var) that selects
   an account for that one call only, leaving the active pointer untouched:

   ```
   $ rp volume list --account personal
   $ RP_ACCOUNT=personal rp volume list
   ```

   One tier above it, an exported `RUNPOD_API_KEY` always wins over every
   stored source, including `--account` — the guaranteed per-command override
   for scripts and CI:

   ```
   $ RUNPOD_API_KEY=<key> rp volume list
   ```

   The focused guide to the per-call override — including the
   `RUNPOD_API_KEY_FILE` form for file-held tokens — is
   [Target a single command at a named account without
   switching](per-command-account.md).

## S3 keys are separate

`rp volume sync` rides the S3-compatible API and needs its own key pair,
distinct from the REST API key. Store it at login:

```
$ rp auth login --name work --api-key <key> \
    --s3-access-key <ak> --s3-secret-key <sk>
```

`rp auth status` shows whether S3 keys are configured; they are only needed
for `rp volume sync`.

## Notes

- Resolution order inside `rp` is (highest first): exported
  `RUNPOD_API_KEY`/`RUNPOD_API_KEY_FILE` → `--account`/`RP_ACCOUNT` → the
  active pointer → the `default` file → the single stored account (if exactly
  one) → the user/install `.env` → none.
- Remove an account with `rp auth logout [--name <n>]`; if it was active and
  others remain, the active pointer moves to another stored account.
