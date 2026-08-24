# How-to: debug one serverless worker through its logs

This is a worked task that spans two commands: the logs verb needs a worker
id, and the workers verb is where you get one. The reference pages
(`rp doc serverless workers`, `rp doc serverless logs`) document the
individual flags; this page shows the pair composed into a debugging session.

Goal: find why a serverless worker is misbehaving — job errors, image pull
failures, OOM kills — by streaming that one worker's logs.

## Steps

1. List the endpoint's workers. Read the worker id from the `id` column; the
   `status`, `version`, `dc`, and `image` columns help you pick the right
   one (an `unhealthy` or stale worker is usually the suspect):

   ```
   $ rp serverless workers end_abc
   ```

2. Stream that worker's logs. `--worker` is required — the command refuses
   to run without it, because the stream is per worker:

   ```
   $ rp serverless logs end_abc --worker wrk_abc123
   ```

   Restrict the stream to one source when you know where to look:

   ```
   $ rp serverless logs end_abc --worker wrk_abc123 --source system --tail 200
   ```

## Notes

- `--source container` is the container's stdout/stderr — job output and
  application errors. `--source system` is the host lifecycle log, which is
  where image pull failures and OOM kills appear; omit the flag for both.
- The stream is Server-Sent Events written raw to stdout — it pipes and
  redirects cleanly, there is no `--json`, and Ctrl-C ends it.
- `--tail N` backfills historical lines before going live; `--since
  <rfc3339>` resumes from a timestamp; `--last-event-id <ts>` reconnects
  from the cursor the endpoint emitted on a previous run.
- `rp serverless workers` also prints a summary line (total / running /
  idle / initializing / throttled / unhealthy) and the endpoint version. To
  watch a configuration change roll out across workers, follow it with
  `rp serverless releases <id>`, whose `diff` column shows what changed per
  release.
