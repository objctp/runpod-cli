# How-to: check which datacentres support the S3 API before filling a volume

This is a worked task that spans a stock lookup and a volume creation. The
reference page (`rp doc stock dc`) documents the individual flags; this page
shows the S3-API check composed into the create flow, plus the one scripting
caveat that the flag reference does not make obvious.

Goal: before you `rp volume sync` files into a network volume, confirm the
volume's datacentre exposes the S3-compatible API — only those datacentres can
be reached by the `aws s3 sync` transfer.

## Steps

1. List datacentres with the S3-API column. `rp stock dc` augments the
   datacentre table (`DATACENTER`, `NAME`, `REGION`, `GPUS`) with an
   `S3_API` column:

   ```
   $ rp stock dc
   ```

   `S3_API` reads `yes` for datacentres whose network volumes expose the
   S3-compatible API and is blank otherwise. Pick a datacentre showing `yes`.

2. Create the volume in that datacentre:

   ```
   $ rp volume create --name hf-cache --size 100 --dc EU-RO-1
   ```

   `rp volume create` only *warns* if the datacentre is not S3-API capable;
   the hard refusal happens later in `rp volume sync`, which exits unless the
   volume's datacentre is in the S3 set. So pick an `S3_API: yes` datacentre
   now to avoid a failure at sync time.

3. Fill the volume (transfer rides the S3 API, so it only works where step 1
   said `yes`):

   ```
   $ rp volume sync hf-cache --source ./data
   ```

## Notes

- `S3_API` is shown in the table only, not in `--json`, so you cannot `jq`
  the S3 status out of the JSON output. For scripting, parse the pretty
  table.
- The column uses the same resolver `rp volume create` guards on — a live
  GraphQL `dataCenters { s3apiEnabled }` query with an offline snapshot
  fallback — so the table and the create-time warning agree whenever both
  resolve the same way.
- `rp volume sync` requires the `aws` CLI and `RUNPOD_S3_ACCESS_KEY` /
  `RUNPOD_S3_SECRET_KEY` to be set. Those are S3 API keys from the Runpod
  console (Settings > S3 API Keys), distinct from the control-plane API key.
