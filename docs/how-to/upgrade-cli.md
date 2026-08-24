# How-to: upgrade the CLI to the latest released version from the terminal

This is a worked task for keeping `rp` itself current. The reference page
(`rp doc upgrade`) documents the single flag; this page shows the two supported
invocations and the environment override.

Goal: update the installed `rp` — whether from `main`'s latest release or a
pinned tag — straight from the terminal, without cloning the repository.

## Steps

1. Upgrade to the latest released version. This re-fetches the installer from the
   configured upgrade repository and re-runs it in place:

   ```
   $ rp upgrade
   ```

   The command prints the current and target version, then re-downloads
   `install.sh` and executes it. There is no preview or confirmation step — it
   runs immediately.

2. (Optional) Pin to a specific tagged release instead of latest. Append
   `--version` with a semantic version:

   ```
   $ rp upgrade --version 1.2.3
   ```

   This fetches that tag's own `install.sh` and runs it against that tag's
   payload, so a downgrade behaves identically to an upgrade.

## Notes

- The install is replaced wholesale: the installer re-extracts `rp` into
  `~/.rp` and refreshes the `/usr/local/bin/rp` symlink. Because the whole
  install is rewritten, nothing needs refreshing by hand afterwards.
- The symlink refresh may prompt for `sudo`; run the command in a session that
  can grant it.
- `rp upgrade` requires `curl` (to fetch the installer), `bash` (to run it),
  and `tar` plus a `sha256sum`/`shasum` checksum tool (to unpack and verify
  the payload). It does not require `git` — the installer is pulled from
  `raw.githubusercontent.com`.
- The source repository defaults to `objctp/runpod-cli`. Override it by
  exporting `RP_UPGRADE_REPO` (e.g. `export RP_UPGRADE_REPO=your-org/your-fork`)
  before running `rp upgrade`. Note the override only redirects where
  `install.sh` is fetched from; the fetched installer hardcodes its own
  payload repository, so a fork must also edit the repo variable inside its
  `install.sh` to serve its own tarballs.
- The only accepted options are `--version <x.y.z>` and `--help`. There is no
  `--check`, `--yes`, or `--force` flag.
