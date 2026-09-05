# Runpod CLI (rp)

A small Bash CLI for managing [Runpod](https://runpod.io?ref=a0lqk36q): pods, serverless
endpoints, network volumes, templates, registries, clusters, billing, cost centers,
account balance, Hub listings, SSH keys, and live GPU stock — one API key, plain
output, script-friendly exit codes.

## Scope

`rp` is a personal, Bash-based wrapper around Runpod's APIs — not a replacement
for the official [`runpodctl`](https://github.com/runpod/runpodctl). I built it
because a shell CLI is easy to extend and to wrap other tooling around — and
because a few workflows (notably `volume sync`, plus `catalog` and `cluster`)
and its single-key auth model aren't covered by `runpodctl`. Where commands overlap with `runpodctl`, the shared
flag spellings are accepted as a convenience only.

## Requirements

- Bash 5+
- Standard Unix tools (`curl`, `jq`) — `rp` checks on startup and names anything missing
- `aws` CLI — only for `rp volume sync` / `rp volume ls` (S3 fill and list)
- `huggingface-cli` — optional, only for `rp volume sync --models`

## Install

macOS or Linux (extracts into `~/.rp` and symlinks `/usr/local/bin/rp`, asking
for `sudo` only for that symlink):

```bash
curl -fsSL https://raw.githubusercontent.com/objctp/runpod-cli/main/install.sh | bash
```

The installer verifies a SHA-256 checksum before extracting. Update later with
`rp upgrade` (or re-run the one-liner); pin a version with
`curl ... | bash -s -- --version 1.4.0`.

`rp` also checks for a newer release once a day and prints a one-line notice when
one is available (it names the right command for your install method). Set
`RP_NO_UPDATE_CHECK=1` to disable the check.

> macOS ships Bash 3.2, but `rp` needs Bash 5+. The installer detects this and
> refuses with the fix (`brew install bash`, then restart your shell).

For development (clone + symlink, no download required):

```bash
make install        # symlinks bin/rp onto /usr/local/bin/rp (may need sudo)
# or, without touching /usr/local/bin:
export PATH="$PWD/bin:$PATH"
```

### Alternative installs

The one-line installer above is the primary, recommended path. If you already
live in a package manager, `rp` is also published to Homebrew and npm:

```bash
brew install objctp/tap/rp          # macOS / Linux (Homebrew)
npm install -g @objctp/rp           # Node 22+ (wraps the same bash CLI)
```

Both install the same CLI and take care of the Bash 5+ requirement for you
(`npm` additionally checks for `curl` and `jq` on first run).

Confirm it works:

```bash
rp version          # installed version
rp _ping            # ok: REST auth works (https://api.runpod.io/v2)
```

## Configure

The simplest path is `rp auth login`, which stores your key in a per-user
config (`${XDG_CONFIG_HOME:-$HOME/.config}/rp`) that survives any install method,
including npm global installs. Multiple accounts are supported — each is a
separate file, with one marked active:

```bash
rp auth login                                  # prompts for the key; stored as "default"
rp auth login --name work --api-key <key>      # named account, marked active
rp auth list                                   # show accounts
rp auth switch work                            # change the active account
rp auth status                                 # show the active account + key source
```

`--account <name>` on any command uses a specific account for that call.
Alternatively, set the variables directly (an exported `RUNPOD_API_KEY` always
wins over the stored config):

| Variable | Where to get it | Required for |
|---|---|---|
| `RUNPOD_API_KEY` | Console → Settings → **API Keys** | everything |
| `RUNPOD_API_KEY_FILE` | path to a file holding the key (e.g. a mounted K8s secret) | everything (alternative to `RUNPOD_API_KEY`) |
| `RUNPOD_S3_ACCESS_KEY` | Console → Settings → **S3 API Keys** (your `user_…` id) | `volume sync` / `ls` |
| `RUNPOD_S3_SECRET_KEY` | Console → Settings → **S3 API Keys** (an `rps_…` key, shown once) | `volume sync` / `ls` |
| `HF_TOKEN` | huggingface.co → Access Tokens | `volume sync --models` (gated models) |
| `RP_MODEL_CACHE` | any writable directory | `volume sync --models` download cache (default: `.cache/models` inside rp's install folder) |

The S3 key pair is **separate** from the REST API key — create it from its own
console page. `rp auth login` writes the key file at mode `600` (dir `700`); the
CLI also warns if a manually-placed `.env` is group- or world-readable.

## Quick start

A representative tour — check stock, provision shared storage, run a pod, and
stand up a scale-to-zero serverless endpoint:

```bash
rp stock dc                                         # pick a datacentre, e.g. EU-RO-1
rp volume create --name shared-data --size 100 --dc EU-RO-1
rp pod create --name dev --image nvcr.io/nvidia/pytorch:23.10-py3 \
    --gpu NVIDIA L4 --volume-gb 100
rp serverless create --name my-endpoint --template <id> \
    --network-volume shared-data --gpus-from-volume shared-data \
    --workers-min 0 --workers-max 3 --idle 600
rp serverless run <id> --input '{"prompt":"hello"}'   # submit a job
```

`--network-volume` auto-scopes the endpoint to that volume's datacentre;
`--gpus-from-volume` builds the GPU fallback list from types in stock, and the
volume mounts at `/runpod-volume` on serverless workers. To deploy from a Hub
listing instead of a template, use `serverless create --hub-id <listing-id>`
(resolve listings with `rp hub search` / `rp hub get`).

Beyond the basics: `rp serverless batch` (beta) submits many requests to an
endpoint as one managed unit — create, add, finalize, then watch with `batch
get`; `rp serverless run --worker-id <id>` pins a job to one worker on a
load-balanced endpoint; `rp stock gpu --mig` lists partitionable GPU slices,
which `--exclude-gpu` subtracts from a serverless pool; `rp cluster pods add`
scales out a running cluster.

For command reference and worked examples, use `rp doc` (in-shell) or the docs
site — both are generated from the same source as the CLI, so they never fall
behind a release:
- [`docs/`](docs/index.md)
- In-shell: `rp --help`, `rp <resource> --help`, `rp doc <command> [<verb>]`

## Good to know

- **S3 fills need an S3-capable datacentre** — `rp stock dc` checks live which
  datacentres support S3 fills, so its S3 column is always current; `rp volume
  create` warns if `--dc` is not S3-capable (and `volume sync` refuses).
- **High-performance volumes need a tier-capable datacentre** — `rp volume
  create --type HIGH_PERFORMANCE` warns when the datacentre doesn't offer that
  tier; `rp stock dc --volume-type HIGH_PERFORMANCE` marks the ones that do.
- **GPU availability is account-wide, not per-datacentre** — `rp volume gpus`
  and `--gpus-from-volume` reflect global availability; the volume's own
  datacentre still gates whether provisioning actually succeeds.
- **Re-running `create` is safe for `volume`, `template`, and `serverless`** —
  an existing resource with the same name is returned, not duplicated; pass
  `--force` to duplicate anyway. `pod` and `registry` `create` always create
  new ones and may duplicate on re-run.
- **`volume sync --models` is a double hop** (HuggingFace → local cache → S3).
  Fine for once-and-rarely fills; use `--source <dir>` for a single hop.
- **Cost centers are local** — `rp cost-center` tags resources into named
  buckets and rolls up per-project spend from the billing endpoints. Runpod's
  own Cost Centers are console-only (no API), so the tagging lives in a
  per-user state file; `--cost-center` on the pod / serverless / volume /
  cluster create verbs assigns at create. Works for a solo account running
  several projects side by side.
- **Stock and prices drift** — re-run the CLI before each booking.

## For scripts and CI

- **Scriptable exit codes** — `0` success · `1` transport/API/general · `2`
  usage · `3` auth (no key/creds) · `4` not-found. Branch on `$?` rather than
  grepping stderr.
- **Rate limits are surfaced** — the CLI warns when a quota window is empty
  (the next request would 429), and a 429 error names the server's wait.
- **List paging is client-side** — Runpod's REST v2 has no server-side
  pagination yet, so `--limit` / `--cursor` slice the already-fetched list
  locally.
- **`rp api` is a raw escape hatch** — `rp api <METHOD> <path>` reaches any v2
  route the typed commands don't wrap yet (e.g. a brand-new endpoint).
- **runpodctl aliases** — several commands also accept `runpodctl`-style flag
  spellings (e.g. `--gpu-id`, `--data-center-ids`) alongside `rp`'s own. Run
  `rp doc <command> <verb>` to see which apply.
- **`--insecure`** (alias `-k`, or `RP_INSECURE_TLS=1`) — skips TLS certificate
  verification for in-pod runs where the CA bundle can't validate the API.
  Traffic stays encrypted; the server identity is not checked.

## Development

Lint, format, and tests are wired up via `make`:

```bash
make fmt        # shfmt (2-space indents)
make lint       # shellcheck
make test       # bashunit (tests/)
make check      # lint + test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the repo layout, code style, and how
to add a command or library helper.
