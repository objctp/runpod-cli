# How-to: read a command's documentation and worked examples without leaving the terminal

This is a worked task covering the two in-shell routes `rp` offers for learning a
command. The reference pages (`rp doc …`) are generated from the source
comments, but this guide is hand-written because it explains *how to read the
docs*, not a single command's flags.

Goal: get the flags, the gotchas, and a runnable example for any command — pod
create, serverless create, stock gpu, and so on — straight from your shell.

## Two routes, two depths

`rp` gives you a terse summary and a full reference. Use the summary to remind
yourself of flag spelling; use the reference before you run something for the
first time.

### 1. `--help` — the terse flag summary

`--help` works at every level: the top level, a command, or a verb. It lists the
flags and nothing else:

```
$ rp --help
$ rp serverless --help
$ rp serverless create --help
```

Use this when you know the command and just need to recall a flag name.

### 2. `rp doc` — the full reference with worked examples

`rp doc <command> [verb] [sub-verb]` renders the documentation block embedded in
the command's source: a one-line summary, the full usage, every option, the
**Notes** (constraints and caveats that `--help` omits), **Examples** (runnable
commands), and the **API** line naming the endpoint the verb hits:

```
$ rp doc                            # every command with a one-line summary
$ rp doc serverless                 # command overview + its verbs
$ rp doc serverless create          # one verb: options, notes, examples, API
$ rp doc stock gpu                  # another single-verb example
$ rp doc registry delegations       # a group verb's sub-verbs
$ rp doc registry delegations create  # one sub-verb
```

The command name may be abbreviated to a prefix, which resolves to the first
alphabetical match — an ambiguous prefix (`rp doc s`) silently picks one
rather than erroring, so prefer prefixes that are unique:

```
$ rp doc serv                       # resolves to rp doc serverless
```

## Why prefer `rp doc` before a first run

`--help` shows flags; `rp doc` explains them. Two things the verb pages carry
that `--help` does not:

- **Notes** — constraints and traps. For `rp serverless create`, for instance,
  the page flags that `--env` is *not* aliased to runpodctl's `--env` (the
  shapes differ), that `--idle` is ignored under `REQUEST_COUNT` scaling, and
  that `--min-cuda-version` is accepted but dropped with a warning. You only
  learn these from `rp doc`.
- **API** — the exact endpoint the verb calls (e.g. `API: POST /v2/serverless`),
  so you can cross-check against the Runpod docs without leaving the terminal.

For a command you are about to run, `rp doc <command> <verb>` is the
in-terminal equivalent of the online reference pages.

## Notes

- `rp doc` reads only user-facing commands; library internals are never
  documented there.
- `rp doc` with no arguments prints a catalogue of every command and its
  one-line summary — a good starting point when you are not sure which command
  you need.
- The `rp doc` output is generated from source comments, so it always matches
  the installed binary; the online manual can lag a release.
