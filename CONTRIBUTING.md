# Contributing

`rp` is a Bash 5+ CLI: a thin dispatcher (`bin/rp`) sourcing shared helpers
(`lib/`), with one file per resource (`commands/`) and a bashunit suite
(`tests/`). It talks to three RunPod APIs directly — REST, GraphQL, and the
S3-compatible API. The design context is in [PRD.md](PRD.md).

## Repo layout

```
bin/rp            entry point — loads .env, sources lib/, dispatches to commands/
lib/              shared helpers (common, http, graphql, s3, args, json, validate, lookup)
commands/         one file per resource (volume, endpoint, pod, template, registry, billing, stock)
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
   through `rp::graphql <query> [variables]` (GraphQL). Both die on error; both
   require `RUNPOD_API_KEY`.
5. Format output with `rp::table <json> field1 field2 …` for human lists; honour
   `--json` to print the raw API response instead.
6. Add a `tests/functional/<resource>_test.sh` covering the happy path and the
   argument errors. Run `make check` until green.

The existing `commands/volume.sh` is the fullest reference — REST, GraphQL, S3,
idempotent create, and `--json` all appear there.

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
