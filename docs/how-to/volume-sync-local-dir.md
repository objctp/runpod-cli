# How-to: fill a volume from a local directory in a single hop

This is a worked task for uploading files you already have on disk. The
reference page (`rp doc volume sync`) documents the individual flags; this page
shows the local-directory path. For the Hugging Face download-and-upload path,
see [Cache a Hugging Face model in a volume for serverless workers](model-cache.md).

Goal: copy a local directory into a network volume directly, in one transfer hop,
rather than fetching from Hugging Face first.

## Steps

1. Pick a datacentre whose network volume exposes the S3 API (the only
   datacentres `rp volume sync` can reach):

   ```
   $ rp stock dc
   ```

2. Create the volume in that datacentre:

   ```
   $ rp volume create --name models --size 100 --dc EU-RO-1
   ```

3. Sync the local directory into the volume. `--source` takes a local path and
   runs a single `aws s3 sync` straight to the volume; files land under the
   default `models` prefix, so the on-volume path is `/models/...`:

   ```
   $ rp volume sync models --source ./checkpoints
   ```

   Add `--prefix <p>` to place the contents under a different key prefix:

   ```
   $ rp volume sync models --source ./checkpoints --prefix runs/2026-08
   ```

## Notes

- `--source` is a true single hop: the CLI runs one `aws s3 sync` from your
  local directory to `s3://<volume-id>/<prefix>`. This differs from
  `--models`, which downloads each repo to a local cache with
  `huggingface-cli` and then uploads it — two hops.
- If both `--source` and `--models` are given, `--source` wins and `--models`
  is ignored silently.
- The source must be an existing local directory; a missing path is an error.
- Prerequisites: the `aws` CLI, plus `RUNPOD_S3_ACCESS_KEY` /
  `RUNPOD_S3_SECRET_KEY` (S3 API keys from the console, not your Runpod API
  key), and a volume whose datacentre exposes the S3 API — enforced up front by
  `rp volume sync` via `rp::is_s3_dc`. `rp stock dc` lists the qualifying
  datacentres.
- `rp volume sync` is a sync: re-running transfers only what changed and never
  deletes files already on the volume.
- The transfer is one-directional (upload). There is no `rp volume download`;
  to fetch files back, run `aws s3 sync` yourself against the volume's
  `s3api-<dc>.runpod.io` endpoint with the same credentials.
