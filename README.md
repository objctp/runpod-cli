# RunPod CLI (rp)

A small Bash CLI for managing RunPod infrastructure: network volumes, serverless
endpoints, pods, templates, registries, billing, account balance, Hub listings,
SSH keys, and live GPU stock. It speaks three RunPod APIs directly — REST API v2
for CRUD, GraphQL for account/hub/ssh/S3-datacentre stock, and the S3-compatible
API for filling volumes — so it covers the same ground as `runpodctl` for the
work in this repo.

It exists to stand up a self-hosted OCR service on RunPod (GLM-OCR, Infinity-Parser2-Flash,
DeepSeek-OCR-2 on serverless, scale-to-zero, behind a shared network volume). This
file is just how to run the tool.

## Requirements

- Bash 5+
- Core tools (`curl`, `jq`, `awk`, `head`, `paste`) — `rp` checks for these on startup and names anything missing
- `aws` CLI — only for `rp volume sync` / `rp volume ls` (S3 fill and list)
- `huggingface-cli` — optional, only for `rp volume sync --models`

macOS ships Bash 3.2; install Bash 5 first (`brew install bash`).

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

For development (clone + symlink, no download):

```bash
make install        # symlinks bin/rp onto /usr/local/bin/rp (may need sudo)
# or, without touching /usr/local/bin:
export PATH="$PWD/bin:$PATH"
```

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
| `RUNPOD_S3_ACCESS_KEY` | Console → Settings → **S3 API Keys** (your `user_…` id) | `volume sync` / `ls` |
| `RUNPOD_S3_SECRET_KEY` | Console → Settings → **S3 API Keys** (an `rps_…` key, shown once) | `volume sync` / `ls` |
| `HF_TOKEN` | huggingface.co → Access Tokens | `volume sync --models` (gated models) |
| `RP_MODEL_CACHE` | any writable directory | `volume sync --models` download cache (default `$RP_ROOT/.cache/models`) |

The S3 key pair is **separate** from the REST API key — create it from its own
console page. The CLI warns if `.env` is group- or world-readable, so tighten it:

```bash
chmod 600 .env
```

## Quick start — the OCR workflow

Stand up one shared network volume, fill it with the three models, build a
serverless template per model, then deploy an endpoint from each template.

```bash
rp stock dc                                         # pick an S3-API-supported datacentre, e.g. EU-RO-1
rp volume create --name ocr-models --size 20 --dc EU-RO-1
rp volume sync ocr-models --models glm,flash,deepseek
rp volume gpus ocr-models                           # GPU types that can mount this volume

# One serverless template per model (repeat --env per var). The worker image is
# the vLLM worker behind Hub listing cm8h09d9n — confirm its tag/env before deploy:
rp template create --name glm-ocr --serverless \
    --image <vllm-worker-image> \
    --env MODEL_NAME=glm \
    --env MODEL_PATH=/runpod-volume/models/glm

# Deploy from that template (its id is the last line above); repeat per model.
rp serverless create --name glm-ocr --template <glm-ocr-template-id> \
    --network-volume ocr-models --gpus-from-volume ocr-models \
    --workers-min 0 --workers-max 3 --idle 600
rp serverless scale <id> --min 0 --max 1
```

`--network-volume` auto-scopes the endpoint to that volume's datacentre;
`--gpus-from-volume` builds the GPU fallback list from the types currently in
stock. The volume mounts at `/runpod-volume` on serverless workers, so point the
serving template's model path there (for example `/runpod-volume/models/glm`).
`template create` and `serverless create` are **idempotent by name** — a re-run
returns the existing id; pass `--force` to duplicate. `template create --env` is
repeatable. To deploy straight from a Hub listing instead of a template, use
`serverless create --hub-id <listing-id>` (resolve listings with `rp hub search` /
`rp hub get`).

## Commands

Run `rp --help` or `rp <resource> --help` for the full flag list. Add `--json`
to any `list` / `get` command for raw API output.

| Resource | Verbs |
|---|---|
| `volume` | `create --name --size --dc` · `list` · `get <id>` · `update <id>` · `delete <id>` · `sync <name> [--source <dir> \| --models a,b,c] [--prefix models]` · `ls <name>` · `gpus <name> [--gpu id,id]` |
| `serverless` | `create --template <id> --gpu <type,..> | --gpus-from-volume <name> [...] [--execution-timeout <s>] [--network-volume <name> | --network-volume-id <id> | --network-volume-ids id,id] [--workers-min N] [--workers-max N] [--idle S] [--gpu-count N] [--flashboot] [--scaler-type T] [--scaler-value V] [--hub-id <listing-id>] [--force]` · `list` · `get <id>` · `update <id> [--workers-min N] [--workers-max N] [--idle S] [--gpu <ids>] [--gpu-count N]` · `scale <id> --min N --max N [--idle S]` · `delete <id>` · `run <id> --input '<json>' | --input-file <path|-> [--sync|--async] [--timeout <s>]` (`--hub-id` deploys from a Hub listing — the listing is fetched via GraphQL, the endpoint created via REST v2; `run` submits a job on the data plane — `api.runpod.ai/v2` — waiting via `/runsync` by default, or queuing via `/run` with `--async`) |
| `pod` | `create --image <img> [...]` · `update <id> [--container-disk-gb N] [--volume-gb N] [--name <n>] [--image <img>] [--ports a/b] [--env K=V] [--start-cmd a,b]` · `list` · `get <id>` · `start \| stop \| restart <id>` (`reset` is an alias for `restart`; v2 dropped it) · `delete <id>` |
| `template` | `create --name --image [--serverless] [--docker-cmd a,b] [--env K=V]… [--ports a/b] [--volume-gb N] [--container-disk-gb N] [--category <c>] [--force]` · `list` · `get <id>` · `search <name-substring>` · `delete <id>` |
| `registry` | `create --name --username [--password <p>]` · `list` · `get <id>` · `delete <id>` |
| `billing` | `pods` · `serverless [id]` · `public-endpoints` · `clusters` · `volumes` · `all` |
| `account` | `[info]` (balance + spend; GraphQL) |
| `hub` | `search <query>` · `get <listing-id>` (GraphQL) |
| `ssh` | `list-keys` · `add-key <file\|->` · `remove-key <fp\|key>` · `info <pod-id>` (GraphQL) |
| `stock` | `gpu` · `dc` (S3-API datacentres flagged) |

`make` exposes a few shortcuts: `make stock` (GPU + DC stock), `make volumes` /
`serverless` / `pods` (list each), `make destroy` (lists everything you may want
to tear down).

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
- **`endpoint` was renamed `serverless`** (REST API v2). The old resource name
  still works but prints a deprecation warning; `rp billing endpoints` likewise
  aliases `rp billing serverless` (use `public-endpoints` for the public-endpoint
  product).
- **Stock and prices drift** — re-run the CLI before each booking.
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
