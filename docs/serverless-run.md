# rp serverless run
Submit a job to a deployed endpoint on the data plane.

```
rp serverless run <id> --input '<json>' | --input-file <path|->
                    [--sync|--async] [--worker-id <id>]
                    [--affinity soft|strict|strict-resume] [--timeout <s>] [--json]
```

## Arguments

```
  <id>             endpoint id — from `rp serverless list`
```

## Options

```
  --input '<json>'          job input as a JSON string
  --input-file <path|->     read job input from a file, or - for stdin
  --sync                    block until the job completes (default)
  --async                   queue and print the job id instead of waiting
  --worker-id <id>          pin the job to one worker on a load-balanced
                            endpoint (X-Runpod-Worker-Id request header);
                            ids come from `rp serverless workers <id>` or
                            the response header of a previous run
  --affinity soft|strict|strict-resume
                            affinity mode for --worker-id (default: soft)
  --timeout <s>             request timeout in seconds (default: 300)
  --json                    print the raw API response
```

## Notes
  --input and --input-file are mutually exclusive, as are --sync and --async.
  The body is wrapped as { "input": <json> } and POSTed to the endpoint's
  runsync (or run, with --async) route on the data plane.
  --worker-id/--affinity apply to load-balanced endpoints and compose with
  --sync/--async alike. The header value is "[mode ]<id>": soft sends the
  bare id (best-effort — the job falls back to normal selection when the
  worker is unavailable; there is no literal "soft" token), strict sends
  "strict <id>" (only that worker; the request waits up to ~5 minutes and
  answers 400 `worker_timeout` on timeout, 404 `affinity_worker_gone` when
  the worker is gone), strict-resume sends "strict-resume <id>" (strict,
  plus it resumes a scaled-down worker before routing).
  --affinity without --worker-id is a usage error.
  Every load-balancer response also carries X-Runpod-Worker-Id; human mode
  prints it ("served by worker: …") so the next request can be pinned.
  Release the pin when done by omitting --worker-id, so the worker can go
  idle.

## Examples

```
# Run a synchronous job with inline input
$ rp serverless run end_abc --input '{"prompt":"hi"}'

# Submit a job from a file and return immediately
$ rp serverless run end_abc --input-file job.json --async

# Pin a session to one worker (strict), then release the pin
$ rp serverless run end_abc --input '{"prompt":"hi"}' --worker-id pod-abc123 --affinity strict
```

**API:** `POST /v2/{id}/runsync  (or /run with --async)`

