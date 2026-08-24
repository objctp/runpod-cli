# How-to: submit a serverless job asynchronously and poll it to completion

This is a worked task for long-running jobs. The reference pages
(`rp doc serverless run`, `rp doc serverless status`) document the individual
flags; this page shows the two commands composed into a submit-and-wait loop.
For the synchronous one-shot path, see
[Submit a job to a serverless endpoint with a JSON input
payload](serverless-run-json-payload.md).

Goal: queue a job with `--async`, capture its job id, and drive it to a
terminal state from a script — without holding one HTTP request open for the
whole run.

## Steps

1. Queue the job. `--async` returns immediately; the confirmation goes to
   stderr and the **job id is printed on stdout**, so capture it directly:

   ```
   $ JOB=$(rp serverless run end_abc --input '{"prompt":"hi"}' --async)
   ```

2. Check the job whenever you like. `rp serverless status <endpoint-id>
   <jobId>` prints the job payload and exits with the job's terminal-status
   code:

   ```
   $ rp serverless status end_abc "$JOB"
   ```

3. Poll to completion. The exit code alone cannot drive the loop — both
   `COMPLETED` and the in-flight states exit 0 — so read `.status` until it
   is terminal, then use the exit code as the verdict:

   ```
   $ while :; do
       out=$(rp serverless status end_abc "$JOB" --json)
       s=$(printf '%s' "$out" | jq -r '.status')
       case "$s" in
         COMPLETED | FAILED | CANCELLED | TIMED_OUT) break ;;
       esac
       sleep 10
     done
   $ rp serverless status end_abc "$JOB" >/dev/null && echo done || echo "job failed: $s"
   ```

## Notes

- Exit-code contract for `rp serverless status`: `0` when the job is
  `COMPLETED` **or** still in flight (`IN_QUEUE` / `IN_PROGRESS`); `1` for
  the terminal failures `FAILED`, `CANCELLED`, and `TIMED_OUT`. The payload
  still prints on failure, so the job's error is visible.
- Both commands take the endpoint id and the job id verbatim; neither
  resolves names. `--json` on `status` prints the raw response for scripting.
- The submission rides the data plane (`POST /{id}/run`); `--timeout <s>`
  on `run` bounds that submission request (default `300`), not the job's
  total runtime.
- To watch what a job did to a worker — or debug one that never starts — see
  [Debug one serverless worker through its logs](serverless-worker-logs.md).
