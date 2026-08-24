# rp volume sync
Upload a local directory or Hugging Face models to a volume.

```
rp volume sync <name> (--source <dir> | --models <owner/repo,…>)
                      [--prefix <p>]
```

## Arguments

```
  <name>                   network volume name — from `rp volume list`
```

## Options

```
  --source <dir>           local directory to upload
  --models <owner/repo,…>  Hugging Face repo slugs to fetch, then upload
  --prefix <p>             key prefix inside the volume (default: models)
```

## Notes
  Give one source or the other. With neither, the command exits with a usage
  error; with both, --source wins and --models is ignored silently.
  The volume's datacentre must expose the S3 API or the command refuses to
  run. `rp stock dc` marks which datacentres qualify.
  Transfer is `aws s3 sync`, so the aws CLI must be installed and
  RUNPOD_S3_ACCESS_KEY and RUNPOD_S3_SECRET_KEY must be set. Those are S3 API
  keys from the console, not your Runpod API key. The read timeout is raised
  to 7200 seconds so large transfers survive.
  The two sources lay out differently: --source copies a directory's
  contents to <prefix>/, whilst --models places each repo under
  <prefix>/<owner>/<repo>/.
  --models needs huggingface-cli and downloads to a local cache first —
  $RP_MODEL_CACHE, or .cache/models under the rp install. Any well-formed
  owner/repo slug is accepted; there is no curated list.
  Being a sync, a re-run transfers only what changed and deletes nothing
  already on the volume.
  Progress is the aws CLI's own output, so there is no --json.

## Examples

```
# Upload local checkpoints under a dated prefix
$ rp volume sync models --source ./checkpoints --prefix runs/2026-08

# Mirror named Hugging Face models into the volume
$ rp volume sync models --models meta-llama/Llama-3-8B,google/gemma-2b

# Serve the cached model from the same volume on a serverless endpoint
$ rp serverless create --name my-endpoint --template <id> \
    --network-volume models --gpus-from-volume models \
    --workers-min 0 --workers-max 3 --idle 600

# workers then load from /models/<owner>/<repo> (volume root + sync prefix)
```

**API:** `GET /v2/network-volumes/{id}, then `aws s3 sync` to s3api-<dc>.runpod.io`

