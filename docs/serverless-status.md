# rp serverless status
Check the status of a job submitted earlier on a deployed endpoint.

```
rp serverless status <id> <jobId> [--json]
```

## ARGUMENTS

```
  <id>             endpoint id — from `rp serverless list`
  <jobId>          job id returned by `rp serverless run --async`
```

## OPTIONS

```
  --json           print the raw job-status envelope
```

## NOTES
  The call rides the data plane (api.runpod.ai/v2), distinct from the
  control-plane REST. stdout is the job payload (pretty in human mode), so a
  FAILED job's `error` is still visible. Exit code mirrors runpodctl:
  0 when the job is COMPLETED (and while it is IN_QUEUE / IN_PROGRESS),
  1 when the job ends FAILED / CANCELLED / TIMED_OUT.

## EXAMPLES

```
  rp serverless status end_abc job-60902e6c-0a1
```

**API:** `GET /{id}/status/{jobId}`

