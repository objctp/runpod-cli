# RunPod CLI (rp)

A small Bash CLI for managing [RunPod](https://runpod.io?ref=a0lqk36q) infrastructure: network volumes, serverless
endpoints, pods, templates, registries, billing, account balance, Hub listings,
SSH keys, and live GPU stock. It speaks three RunPod APIs directly — REST API v2
for CRUD, GraphQL for account/hub/ssh/S3-datacentre stock, and the S3-compatible
API for filling volumes — so it covers the same ground as `runpodctl` for the
work in this repo.

It is a general-purpose client for the RunPod v2 APIs — not tied to any one
workload. This file is just how to run the tool; the quick start below tours what
it can do, from volumes and pods to serverless endpoints and billing.

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

A tour of the breadth: check stock, provision shared storage, run an on-demand
pod, and stand up a scale-to-zero serverless endpoint.

```bash
rp stock dc                                         # pick a datacentre, e.g. EU-RO-1
rp stock gpu                                        # see GPU types and prices

# A network volume for shared model/data storage (needs an S3-API datacentre).
rp volume create --name shared-data --size 100 --dc EU-RO-1
rp volume gpus shared-data                          # GPU types that can mount this volume

# An on-demand pod for interactive dev / training — attach the volume for persistence.
rp pod create --name dev --image nvcr.io/nvidia/pytorch:23.10-py3 \
    --gpu NVIDIA L4 --volume-gb 100

# A serverless endpoint for scale-to-zero inference. Build a template once, deploy
# an endpoint from it (its id prints on the last line):
rp template create --name my-worker --serverless \
    --image <your-worker-image> \
    --env MODEL_PATH=/runpod-volume/models/my-model
rp serverless create --name my-endpoint --template <my-worker-template-id> \
    --network-volume shared-data --gpus-from-volume shared-data \
    --workers-min 0 --workers-max 3 --idle 600
rp serverless run <id> --input '{"prompt":"hello"}'   # submit a job
```

`--network-volume` auto-scopes the endpoint to that volume's datacentre;
`--gpus-from-volume` builds the GPU fallback list from the types currently in
stock. The volume mounts at `/runpod-volume` on serverless workers, so point the
serving template's model path there (for example `/runpod-volume/models/my-model`).
`template create` and `serverless create` are **idempotent by name** — a re-run
returns the existing id; pass `--force` to duplicate. `template create --env` is
repeatable. To deploy straight from a Hub listing instead of a template, use
`serverless create --hub-id <listing-id>` (resolve listings with `rp hub search` /
`rp hub get`). `pod create` always provisions a fresh pod.

### Example use case — a scale-to-zero inference API

The same primitives serve any model behind a shared volume. Fill a volume with
weights from HuggingFace, then deploy a serverless endpoint:

```bash
rp stock dc
rp volume create --name model-store --size 50 --dc EU-RO-1
rp volume sync model-store --models <owner/repo>,<owner/repo>   # e.g. meta-llama/Llama-3-8B,meta-llama/Llama-3-70B
rp volume gpus model-store

rp template create --name my-worker --serverless \
    --image <worker-image> \
    --env MODEL_NAME=my-model \
    --env MODEL_PATH=/runpod-volume/models/my-model
rp serverless create --name my-endpoint --template <my-worker-template-id> \
    --network-volume model-store --gpus-from-volume model-store \
    --workers-min 0 --workers-max 3 --idle 600
rp serverless run <id> --input '{"prompt":"hello"}'   # submit a job
```

`rp volume sync --models` takes HuggingFace repo slugs and downloads each into
the volume's `models/` prefix.

### Example use case — a training job on a persistent pod

The same volume primitives back long-running pods. Sync a local dataset into a
volume, launch a pod that mounts it, then watch spend while it runs:

```bash
rp stock gpu                                         # pick a GPU + datacentre
rp volume create --name datasets --size 200 --dc EU-RO-1
rp volume sync datasets --source ./my-corpus --prefix data   # single-hop local -> S3

rp pod create --name trainer --image nvcr.io/nvidia/pytorch:23.10-py3 \
    --gpu NVIDIA A100-80GB --volume-gb 200
rp pod get trainer                                   # wait for 'RUNNING'
rp billing pods                                      # live per-pod spend

# Tear down when finished.
rp pod stop trainer
rp pod delete trainer
```

`rp volume sync --source <dir>` uploads a local directory in a single hop
(local → S3), unlike `--models` which routes via a HuggingFace cache. Pods are
billed while `RUNNING`, so `rp pod stop` / `rp pod delete` stops the meter.


Run `rp --help` or `rp <resource> --help` for the full flag list.

Every `list` and `get` command accepts `--json` for raw API output and `--jq <filter>`
for field selection. `list` commands also accept `--limit N` / `--cursor N` for paging
large result sets.
Pagination is client-side today (shaped to match the server cursor RunPod will
add), so the same flags will forward server-side without a CLI change. For
anything the resource verbs don't cover, `rp api <METHOD> <path>` is a raw escape
hatch over the same transport — it supports `--body <json>` (prefix `@` to read
a file), `--plane rest|api`, `--jq`, `--limit`, and `--cursor`.

| Resource | Verbs |
|---|---|
| `volume` | `create --name --size --dc` · `list` · `get <id>` · `update <id>` · `delete <id>` · `sync <name> [--source <dir> \| --models a,b,c] [--prefix models]` · `ls <name>` · `gpus <name> [--gpu id,id]` |
| `serverless` | `create --template <id> --gpu <type,..> \| --gpus-from-volume <name> [...] [--execution-timeout <s>] [--network-volume <name> \| --network-volume-id <id> \| --network-volume-ids id,id] [--type QUEUE\|LOAD_BALANCER] [--workers-min N] [--workers-max N] [--idle S] [--gpu-count N] [--flashboot] [--env K=V]… [--scaler-type T] [--scaler-value V] [--hub-id <listing-id>] [--force] [--registry <id>]` · `list` · `get <id>` · `update <id> [--workers-min N] [--workers-max N] [--idle S] [--gpu <ids>] [--gpu-count N] [--registry <id>]` · `scale <id> --min N --max N [--idle S]` · `delete <id>` · `workers <id>` · `releases <id>` · `logs <id> --worker <workerId>` · `run <id> --input '<json>' \| --input-file <path\|-> [--sync\|--async] [--timeout <s>]` (`--hub-id` deploys from a Hub listing — the listing is fetched via GraphQL, the endpoint created via REST v2; `--env` overlays the template's env, the user's value winning per key; `run` submits a job on the data plane — `api.runpod.ai/v2` — waiting via `/runsync` by default, or queuing via `/run` with `--async`) |
| `pod` | `create --image <img> [--gpu <id>] [--cpu-flavor <id> --vcpu <n>] [--registry <id>] [...]` · `update <id> [--container-disk-gb N] [--volume-gb N] [--name <n>] [--image <img>] [--ports a/b] [--env K=V] [--start-cmd a,b] [--registry <id>]` · `list` · `get <id>` · `start \| stop \| restart <id>` (`reset` is an alias for `restart`; v2 dropped it) · `delete <id>` · `logs <id> [--source container|system] [--tail N]` |
| `template` | `create --name --image [--serverless] [--docker-cmd a,b] [--env K=V]… [--ports a/b] [--volume-gb N] [--container-disk-gb N] [--category <c>] [--public true\|false] [--registry <id>] [--force]` · `update <id> [--name <n>] [--image <img>] [--public true\|false] [--registry <id>] [--docker-cmd a,b] [--env K=V]… [--ports a/b] [--container-disk-gb N] [--volume-gb N] [--category <c>] [--serverless]` · `list` · `get <id>` · `search <name-substring>` · `delete <id>` (templates are private unless `--public true`; `update` PATCHes by id and needs at least one field) |
| `registry` | `create --name --username [--password <p>]` · `list` · `get <id>` · `delete <id>` · `delegations <list\|create\|revoke>` |
| `billing` | `pods` · `serverless [id]` · `public-endpoints` · `clusters` · `volumes` · `all` |
| `account` | `[info]` (balance + spend; GraphQL) |
| `hub` | `search <query>` · `get <listing-id>` (GraphQL) |
| `ssh` | `list-keys` · `add-key <file\|->` · `remove-key <fp\|key>` · `info <pod-id>` (GraphQL) |
| `stock` | `gpu` · `cpus` (CPU flavours: id, vCPU range, per-vCPU RAM/price) · `dc` (S3-API datacentres flagged) |
| `api` | `GET\|POST\|PUT\|DELETE <path>` (`<path>` may omit the leading `/`) · `--body <json>` (prefix `@` to read a file) · `--plane rest\|api` · `--jq <filter>` · `--limit N` · `--cursor N` |
| `doc` | `[command] [verb]` (omit to list every command) — prints the source-comment docs for a user-facing command; with a verb, its options/flags; and with a group verb, sub-verb routing (`rp doc serverless`, `rp doc serverless create`, `rp doc registry delegations`, `rp doc registry delegations create`) |
| `upgrade` | `[--version <x.y.z>]` (self-update in place; re-runs the installer) |

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
- **`rp api` is a raw escape hatch** — `rp api <METHOD> <path>` calls the same
  transport as the resource verbs, so it reaches any v2 route the typed commands
  don't wrap yet (e.g. a brand-new endpoint). It honours `--body`, `--plane`,
  `--jq`, `--limit`, and `--cursor`.
- **List paging is client-side** — RunPod's REST v2 has no server-side pagination
  yet, so `--limit` / `--cursor` slice the already-fetched list locally. The flags
  mirror the cursor shape RunPod will add, so they forward server-side later
  without a CLI change.
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
