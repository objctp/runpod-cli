# rp upgrade
Update rp in place from the latest (or a pinned) release.
The public installer is fetched from GitHub and re-run: it re-extracts rp
into ~/.rp and refreshes the /usr/local/bin/rp symlink, so an upgrade
replaces the whole install rather than patching it. --version pins the
installer to a tagged release, running that tag's own installer against that
tag's payload, so a downgrade behaves the same way as an upgrade.

```
rp upgrade [--version <x.y.z>]
```

## Options

```
  --version <x.y.z>  pin the installer to a tagged release (default: latest)
```

## Notes
  The /usr/local/bin/rp symlink step may prompt for sudo.
  rp also checks for a newer release once a day and prints a one-line notice
  when one is available — naming the right command for your install method:
  `rp upgrade`, `npm update -g runpod-cli`, or `brew upgrade runpod-cli`.
  Set RP_NO_UPDATE_CHECK=1 to disable the check.

## Examples

```
# Upgrade to the latest release
$ rp upgrade

# Upgrade to a pinned version
$ rp upgrade --version 1.2.3
```

**API:** `none — downloads and runs the installer from GitHub (RP_UPGRADE_REPO).`

