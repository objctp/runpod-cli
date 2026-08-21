# RunPod CLI (rp)

A small Bash CLI for managing [RunPod](https://runpod.io?ref=a0lqk36q) infrastructure: network volumes, serverless
endpoints, pods, templates, registries, billing, account balance, Hub listings,
SSH keys, and live GPU stock. It speaks three RunPod APIs directly — REST API v2
for CRUD, GraphQL for account/hub/ssh/S3-datacentre stock, and the S3-compatible
API for filling volumes.

## Scope

`rp` is a personal, Bash-based wrapper around RunPod's APIs — not a replacement
for the official [`runpodctl`](https://github.com/runpod/runpodctl). I built it
because a shell CLI is easy to extend and to wrap other tooling around — and
because a few workflows (notably `volume sync`, plus `catalog` and `cluster`)
aren't covered by `runpodctl`. Where commands overlap with `runpodctl`, the shared
flag spellings are accepted as a convenience only.

## Requirements

- Bash 5+
- Core tools (`curl`, `jq`, `awk`, `head`, `paste`) — `rp` checks for these on startup and names anything missing
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
`curl ... | bash -s -- --version 0.1.0`.

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

Both pull the same universal tarball and pin to the released `rp-VERSION.tar.gz`
checksum; `brew` rewrites the shebang to a Bash 5+ and `npm` runs a startup
preflight asserting Bash 5+/jq/curl.

Confirm it works:

```bash
rp version          # installed version
rp _ping            # ok: REST auth works (https://api.runpod.io/v2)
```

## Configure

Copy the example env file and add your keys.

```bash
cp .env.example .env
```

| Variable | Where to get it | Required for |
|---|---|---|
| `RUNPOD_API_KEY` | Console → Settings → **API Keys** | everything |
| `RUNPOD_API_KEY_FILE` | path to a file holding the key (e.g. a mounted K8s secret) | everything (alternative to `RUNPOD_API_KEY`) |
| `RUNPOD_S3_ACCESS_KEY` | Console → Settings → **S3 API Keys** (your `user_…` id) | `volume sync` / `ls` |
| `RUNPOD_S3_SECRET_KEY` | Console → Settings → **S3 API Keys** (an `rps_…` key, shown once) | `volume sync` / `ls` |
| `HF_TOKEN` | huggingface.co → Access Tokens | `volume sync --models` (gated models) |
| `RP_MODEL_CACHE` | any writable directory | `volume sync --models` download cache (default `$RP_ROOT/.cache/models`) |

The S3 key pair is **separate** from the REST API key — create it from its own
console page. The CLI warns if `.env` is group- or world-readable, so tighten it:

```bash
chmod 600 .env
```

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

For command reference and worked examples, use `rp doc` (in-shell) or the docs
site — both are generated from the same source as the CLI, so they never fall
behind a release:
- [`docs/`](docs/index.md)
- In-shell: `rp --help`, `rp <resource> --help`, `rp doc <command> [<verb>]`

## Things worth knowing

- **S3 fill needs an S3-API-supported datacentre** — `rp stock dc` reads the
  `s3apiEnabled` flag live, so its S3 column is always current; `rp volume create`
  warns if `--dc` is not S3-capable (and `volume sync` refuses).
- **Catalog stock is account-wide, not per-datacentre** — `rp volume gpus` and
  `--gpus-from-volume` reflect global availability; the volume's own datacentre
  still gates whether provisioning actually succeeds.
- **REST API v2 is beta** — the control plane defaults to
  `https://api.runpod.io/v2`; pin a different base (or a staging host) with
  `RP_REST_BASE`.
- **`volume sync --models` is a double hop** (HuggingFace → local cache → S3).
  Fine for once-and-rarely fills; use `--source <dir>` for a single hop.
- **Idempotent creates** — `volume`, `template`, and `serverless` `create` return the
  existing resource when the name matches; pass `--force` to duplicate. `pod` and
  `registry` `create` always POST and may duplicate on re-run.
- **`rp api` is a raw escape hatch** — `rp api <METHOD> <path>` calls the same
  transport as the resource verbs, so it reaches any v2 route the typed commands
  don't wrap yet (e.g. a brand-new endpoint). It honours `--body`, `--plane`,
  `--jq`, `--limit`, and `--cursor`.
- **List paging is client-side** — RunPod's REST v2 has no server-side pagination
  yet, so `--limit` / `--cursor` slice the already-fetched list locally. The flags
  mirror the cursor shape RunPod will add, so they forward server-side later
  without a CLI change.
- **Stock and prices drift** — re-run the CLI before each booking.
- **runpodctl aliases** — several commands also accept `runpodctl`-style flag
  spellings (e.g. `--gpu-id`, `--data-center-ids`) alongside `rp`'s own. Run
  `rp doc <command> <verb>` to see which apply.
- **`--insecure`** (alias `-k`, or `RP_INSECURE_TLS=1`) — skips TLS certificate
  verification for in-pod runs where the CA bundle can't validate the API. Traffic
  stays encrypted; the server identity is not checked. Distinct from
  `RP_ALLOW_INSECURE_HTTP`, which refuses plaintext `http://`.
- **Scriptable exit codes** — `0` success · `1` transport/API/general · `2`
  usage · `3` auth (no key/creds) · `4` not-found. Branch on `$?` rather than
  grepping stderr.

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
