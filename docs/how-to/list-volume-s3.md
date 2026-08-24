# How-to: list the contents of a network volume over the S3 API

This is a single-task guide. The reference page (`rp doc volume ls`) documents
every flag; this page shows the call and the prerequisites that the command
does not check for you.

Goal: list the objects stored on a network volume, addressing the volume by its
name and reading through the S3-compatible API.

## Steps

1. (Recommended) Confirm the volume's datacentre exposes the S3 API. Find the
   datacentre first — `rp volume list` prints it in the `DATACENTER` column —
   then look that id up in the stock table:

   ```
   $ rp volume list
   $ rp stock dc
   ```

   Only an `S3_API: yes` datacentre can be reached (see
   [Check which datacentres support the S3 API](s3-datacenter-check.md)).
   `rp volume ls` does not pre-check this itself, so a non-S3 datacentre
   fails later inside `aws s3 ls`.

2. List the volume. The volume is addressed by name and resolved to its id
   internally:

   ```
   $ rp volume ls models
   ```

   To scope the listing to a sub-tree, pass the key prefix with `--path`
   (not `--prefix`):

   ```
   $ rp volume ls models --path models/meta-llama
   ```

   The listing is one level deep; sub-prefixes show as `PRE` entries. The
   output is printed verbatim from `aws s3 ls`.

## Notes

- The flag is `--path`, not `--prefix`. (`rp volume sync` uses `--prefix`; `ls`
  does not.)
- There is no `--json`. The listing is the raw `aws s3 ls` output, so it
  cannot be machine-filtered through `rp`.
- The command requires the `aws` CLI and the `RUNPOD_S3_ACCESS_KEY` /
  `RUNPOD_S3_SECRET_KEY` pair to be set. Those are S3 API credentials from
  the Runpod console (Settings > S3 API Keys), distinct from your
  control-plane API key.
