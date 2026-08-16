# Contributing

`rp` is a Bash 5+ CLI: a thin dispatcher (`bin/rp`) sourcing shared helpers
(`lib/`), with one file per resource (`commands/`) and a bashunit suite
(`tests/`). It talks to three RunPod APIs directly — REST, GraphQL, and the
S3-compatible API.

## Repo layout

```
bin/rp            entry point — loads .env, sources lib/, dispatches to commands/
lib/              shared helpers (common, constants, transport, auth, http, graphql, s3, args, json, validate, resource, paginate, hub, _version) — `transport` is the single curl impl and delegates credential resolution to `auth` (never read `RUNPOD_API_KEY` directly)
commands/         one file per resource (volume, serverless, pod, template, registry, billing, stock, account, hub, ssh, upgrade)
tests/unit/       bashunit unit tests for lib helpers
tests/functional/ bashunit functional tests for commands
Makefile          fmt / lint / test / check + listing shortcuts
.shellcheckrc     shellcheck config
cliff.toml        git-cliff config for CHANGELOG.md
scripts/changelog.sh   regenerates the Unreleased changelog section
.githooks/        post-commit hook keeps CHANGELOG.md current
```

## Setup

```bash
cp .env.example .env        # add RUNPOD_API_KEY at minimum
make install                # or: export PATH="$PWD/bin:$PATH"
make check                  # lint + tests must pass before you commit
```

You need `curl`, `jq`, and Bash 5+ to run the CLI; `shellcheck` and `shfmt` to
run `make check`; `bashunit` to run `make test`.

## Code style

- **Format with shfmt, 2-space indents:** `make fmt`
  (`shfmt -i 2 -w` over `lib commands tests` and `bin/rp`).
- **Lint with shellcheck:** `make lint`. The repo `.shellcheckrc` disables
  `SC1090`/`SC1091` (dynamic sourcing) and `SC2329`, and treats external sources
  as trusted — don't re-enable these casually.
- **`set -euo pipefail`** at the top of executable scripts. Sourced `lib/` and
  `commands/` files do **not** set it (they are sourced into `bin/rp`, which
  already does) — they start with an include guard instead (see below).
- Quote every expansion; prefer `(( ))` for arithmetic and `[[ ]]` for tests.

## Comment Conventions

Comment only when the code itself cannot convey the information: a hidden
constraint, a subtle invariant, a bug workaround, or behaviour that would
surprise a careful reader. Explain **why**, not **what** — if removing the
comment wouldn't confuse a future reader, don't write it.

- **File header** — every script starts with:
  ```bash
  #!/usr/bin/env bash
  #
  # [BRIEF DESCRIPTION OF WHAT THIS SCRIPT DOES]
  # Usage: [SCRIPT_NAME] [ARGUMENTS]
  #
  ```
- **Section dividers** — only when a section exceeds ~50 lines or its complexity
  warrants signposting. Pad the `#` tail to the nearest of 40, 80, or 120:
  ```bash
  ###
  ### :::: [description] :::: ###########
  ###
  ```
  Don't add dividers between short, self-evident sections.
- **Public function docs** — use the structured `Arguments:`/`Returns:` template
  only on public `rp::` functions whose name and arguments don't fully convey the
  contract (non-obvious return codes, argument constraints, side effects, failure
  conditions):
  ```bash
  # [description]
  # Arguments:
  #   $1 - [name]: [description]
  # Returns:
  #   0 - [success description]
  #   1 - [failure description]
  ```
  Private `_` helpers don't need the template, but *why*-style annotation
  comments above them are welcome wherever they explain a hidden constraint or
  surprise.
- **Inline comments** — trailing `#` on the same line. Good: `# 10% of total
  memory`. Bad: `# calculate threshold`.
- **Annotation comments** — a bare `#` line above a block explaining intent.

## The include-guard pattern

Every `lib/*.sh` file begins with a guard so it can be sourced more than once
without redefining functions:

```bash
#!/usr/bin/env bash
[[ -n "${_RP_FOO:-}" ]] && return 0
_RP_FOO=1

rp::foo() { … }
```

`bin/rp` sources `lib/common.sh` first, then the rest of `lib/*.sh`, then the
requested `commands/<resource>.sh`. New helpers go in `lib/`; new resources go
in `commands/`.

## Adding a command (new resource)

1. Create `commands/<resource>.sh` with a guard-free top (it is sourced, not
   executed) and an entry function named exactly `rp::cmd_<resource>` — that is
   what `bin/rp` dispatches to.
2. Handle `--help` / `-h` / `help` first and print usage. Keep usage strings
   identical to the argument-parsing errors so they stay in sync.
3. Parse flags with `rp::args_parse` and read them with `rp::args_get`,
   `rp::args_has`, `rp::args_pos` (see `lib/args.sh`). Booleans are declared in
   `RP_BOOL_FLAGS` inside `lib/args.sh` — add new boolean flags there.
4. Do CRUD through `rp::http <METHOD> <path> [json]` (REST) and reads-through-stock
   through `rp::graphql <query> [variables]` (GraphQL). Both die on error and both
   require a RunPod API token, resolved by `lib/auth.sh` from `RUNPOD_API_KEY` or
   `RUNPOD_API_KEY_FILE` — never read `RUNPOD_API_KEY` from a command or the
   transport; add a credential source in `rp::auth_token` instead.
5. Format output with `rp::table <json> field1 field2 …` for human lists; honour
   `--json` to print the raw API response instead. For list commands, pipe the
   unwrapped array through `rp::paginate` and honour `--jq` / `--limit` / `--cursor`
   (see `rp::resource_list` for the pattern) so paging and field selection work
   uniformly across every resource.
6. Document the command for `rp doc` (see below): give `commands/<resource>.sh`
   the strict intro (a ≤62-char summary ending with `.`, then a description and
   `Usage:`), and add a `# doc: <verb>` block per verb above `rp::cmd_<resource>()`
   in case order, so users can read the options without `--help`.
7. Add a `tests/functional/<resource>_test.sh` covering the happy path and the
   argument errors. Run `make check` until green.

### Documenting a command for `rp doc`

`rp doc` is the command's man page; `--help` stays a terse cheat sheet. It
surfaces source comments only — never library internals — so a command is
self-documenting once its comments are in place. Two sources feed it:

- **Command intro** — the comment block at the top of `commands/<resource>.sh`
  (after the shebang). `rp doc <resource>` prints this as the command overview,
  and `rp doc` (no filter) shows its first line as the catalogue summary. The
  first line is a complete sentence, at most 62 characters, ending with a full
  stop, and carries no `` `rp x` — `` prefix (the catalogue and heading already
  print the name). It is followed by a blank line, a 2–6 line description, a
  blank line, then `Usage:`. Command files use this strict intro; `lib/` helpers
  keep a looser one-line header, since only user-facing commands are documented.
- **Per-verb docs** — one contiguous section of `# doc: <verb>` blocks directly
  above `rp::cmd_<resource>()`, preceded by a
  `### :::: documentation (rp doc <resource>) :::: ###` marker and in the order
  the verbs appear in the command's `case "$verb" in` block (a group verb
  dispatched by an `if [[ "$verb" == … ]]` guard, such as `rp registry
  delegations`, comes first). `rp doc <resource> <verb>` prints the block; as a
  fallback it also reads the comment above the `_<resource>_<verb>` handler.
  Keep both in sync; `rp doc` needs no separate doc file.

Each verb block uses this fixed anatomy — `Summary` and `Usage:` are mandatory,
the rest only when they carry content, and headers never repeat or change order:

    Summary · Usage: · Arguments: · Options: · Notes: · Examples: · API:

Options grammar:

| Spec | Meaning |
|------|---------|
| `<id>` | freeform identifier |
| `N` | bare integer (unit lives in the description) |
| `a\|b` | pipe-separated enum |
| `<thing,…>` | comma-separated list (real ellipsis) |
| `(required)` / `(default: X)` | suffix on a spec |
| `true\|false` | tri-state boolean; the description must say what omitting does |

Align each description at the longest spec in its block plus two columns; order
options required → optional → `--json`/`--jq` last (never alphabetical). Only
document a shared flag (`--json`, `--jq`, `--limit`, `--cursor`, `--force`) where
the verb genuinely supports it. A deprecation rides the `Summary` prefix
(`Deprecated: use \`rp serverless\`.`); an alias is a stub — summary, usage,
notes — never a copy of the target's options.

The canonical reference is `commands/pod.sh` — its
`### :::: documentation (rp doc pod) :::: ###` section demonstrates the full
anatomy; render it with `rp doc pod`.

## Adding a library helper

Put it in `lib/<area>.sh` with the include guard above, prefix the function with
`rp::`, and add a `tests/unit/<area>_test.sh`. Helpers must not call `exit`
directly for expected conditions — use `rp::die` so error formatting stays
consistent.

## Commits and changelog

- Use **Conventional Commits** (`feat:`, `fix:`, `refactor:`, `perf:`, …). They
  drive [CHANGELOG.md](CHANGELOG.md) via `git-cliff`
  (`cliff.toml`) — grouped as Added / Changed / Fixed.
- The `post-commit` hook (`.githooks/post-commit.sh`) regenerates the Unreleased
  section and amends it into the commit, so each commit lands with an up-to-date
  changelog line. If the hook is not active, run
  `git config core.hooksPath .githooks` once, or generate manually with
  `scripts/changelog.sh unreleased`.

## Running tests

```bash
make test          # bashunit tests/
```

Unit tests in `tests/unit/` cover the `lib/` helpers and run without network
access. Functional tests in `tests/functional/` exercise a command's argument
parsing and output shaping; live RunPod calls belong behind a flag or a mock so
`make check` stays hermetic.
