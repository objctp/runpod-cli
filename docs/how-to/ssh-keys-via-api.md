# How-to: add and list SSH public keys on your account

This is a worked task for managing the SSH public keys attached to a RunPod
account — the keys that make provisioned pods reachable over SSH. The
reference page (`rp doc ssh-key`) documents the per-verb flags; this page
shows the workflow composed into real calls, including the raw REST route
underneath the typed commands.

## Steps

1. Use the typed commands. The canonical home for key management is
   `rp ssh-key`:

   ```
   $ rp ssh-key list                       # list registered public keys
   $ rp ssh-key add ~/.ssh/id_ed25519.pub  # add from a file
   $ ssh-keygen -y -f ~/.ssh/id_ed25519 | rp ssh-key add -   # pipe from stdin
   $ rp ssh-key remove <fingerprint|key>   # remove one
   ```

   `rp ssh-key add` registers only the first non-blank line of its input, and
   re-adding a key you already hold is a no-op. `rp ssh-key remove` takes the
   SHA256 fingerprint shown by `rp ssh-key list`, or any unambiguous
   substring of the key line (for example the comment/email) — a fragment
   that matches several keys is rejected rather than removing them all.

2. Or hit the raw REST route. Listing reads the v2 control plane directly:

   ```
   $ rp api GET /account/ssh-keys
   $ rp api GET /account/ssh-keys --jq '.keys'
   ```

   The response is a JSON object with a `keys` array of authorized-key
   lines.

3. To remove or replace keys through the API, fetch-modify-write the whole
   set. The v2 route replaces the **entire** key set on `PUT` — there is no
   add-one / delete-one endpoint:

   ```
   $ rp api PUT /account/ssh-keys --body '{"keys":["ssh-ed25519 AAAA... user@host"]}'
   ```

   That `PUT` overwrites every key you had with exactly the array you send,
   so only call it when you intend to set the complete key set.
   `rp ssh-key add` / `remove` do this read-modify-write for you; use them
   unless you are managing the set in bulk.

## Notes

- `rp ssh list-keys` / `add-key` / `remove-key` still exist as deprecated
  aliases that warn and delegate to these same handlers (same v2 REST
  route); prefer `rp ssh-key`.
- These calls act on whatever the active credentials resolve to. Resolution
  order (highest first): an exported `RUNPOD_API_KEY`/`RUNPOD_API_KEY_FILE`
  → `--account`/`RP_ACCOUNT` → the active pointer. So you can manage keys
  per account:

  ```
  $ rp auth switch work                    # operate on the "work" account
  $ rp ssh-key list --account personal     # or scope a single call
  $ RUNPOD_API_KEY=<key> rp ssh-key list   # or override inline
  ```
