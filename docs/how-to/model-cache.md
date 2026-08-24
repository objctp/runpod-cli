# How-to: cache a Hugging Face model in a volume for serverless workers

This is a worked task that spans several commands. The reference pages
(`rp doc volume sync`, `rp doc serverless create`) document the individual
flags; this page shows them composed into one workflow.

Goal: pull a model into a network volume once, then serve it from a
serverless endpoint whose workers read the files from disk instead of the
Hub — so cold starts skip the download.

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

3. Sync the model into the volume. `rp volume sync --models` fetches with
   `huggingface-cli download` and uploads with `aws s3 sync`; files land
   under the default `models` prefix, so the on-volume path is
   `/models/<owner>/<repo>`:

   ```
   $ rp volume sync models --models meta-llama/Llama-3.1-8B-Instruct
   ```

4. Create the serverless endpoint reusing that volume. `--network-volume`
   attaches it by name and pins the endpoint to the volume's datacentre;
   `--gpus-from-volume` picks in-stock GPU types from the account-wide
   serverless catalogue (a fixed preference list — see
   [Scope a serverless endpoint to a network volume's
   datacentre](serverless-gpus-from-volume.md)):

   ```
   $ rp serverless create --name my-endpoint --template tmpl_abc \
       --network-volume models --gpus-from-volume models \
       --workers-min 0 --workers-max 3 --idle 600
   ```

5. Point the worker at the on-volume path
   `/models/meta-llama/Llama-3.1-8B-Instruct` (the volume's mount root plus
   the sync prefix, owner segment included), not the Hub. No pod or SSH is
   needed for the transfer.

## Notes

- The volume's datacentre must be S3-API capable, and `aws` plus
  `RUNPOD_S3_ACCESS_KEY` / `RUNPOD_S3_SECRET_KEY` must be configured.
- `--models` also needs `huggingface-cli` on PATH; it downloads to a local
  cache (`$RP_MODEL_CACHE`, or `.cache/models` under the `rp` install) before
  uploading.
- `rp volume sync` is a sync: re-running transfers only what changed and
  never deletes files already on the volume.
