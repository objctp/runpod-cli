# How-to: target a single command at a named account without switching

This is a focused task covering the per-call account override. The full
account model — storing accounts, switching the active one, and S3 keys — is
in [Manage multiple RunPod accounts and switching between them per
command](multiple-accounts.md). For every flag and the precise resolution
order, see `rp doc auth`.

Goal: run one `rp` command under a specific stored account while leaving the
active account exactly as it was.

## Steps

1. Confirm the stored account names, then pass the global `--account` flag to
   any command:

   ```
   $ rp auth list
   $ rp volume list --account personal
   ```

2. Or set the `RP_ACCOUNT` environment variable, scoped to the single
   command via a leading assignment:

   ```
   $ RP_ACCOUNT=personal rp volume list
   ```

3. For scripts and CI, an exported `RUNPOD_API_KEY` (or
   `RUNPOD_API_KEY_FILE`, pointing at a file that holds the token — e.g. a
   mounted secret) beats every stored source, `--account` included:

   ```
   $ RUNPOD_API_KEY=<key> rp volume list
   ```

## Notes

- Resolution order (highest first): an explicit exported
  `RUNPOD_API_KEY`/`RUNPOD_API_KEY_FILE` → `--account`/`RP_ACCOUNT` → the
  active pointer → the `credentials.d/default` file → the single account
  present (if exactly one) → the user/install `.env` → none.
- `--account`/`RP_ACCOUNT` selects an account for the one call only; the
  active pointer is never modified. Switching the active account for all
  future calls is `rp auth switch <name>`.
- Within the `--account`/`RP_ACCOUNT` tier, the `RP_ACCOUNT` environment
  variable takes precedence over the `--account` flag if both are set.
- Exit codes are stable for scripting: transport auth failures (HTTP 401/403)
  exit 3, so a CI step can distinguish a credentials problem from a request
  problem (exit 1) or a missing resource (exit 4).
