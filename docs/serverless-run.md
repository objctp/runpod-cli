# rp serverless run
Submit a job to a deployed endpoint on the data plane.

```
rp serverless run <id> --input '<json>' | --input-file <path|->
                    [--sync|--async] [--timeout <s>] [--json]
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
  --timeout <s>             request timeout in seconds (default: 300)
  --json                    print the raw API response
```

## Notes
  --input and --input-file are mutually exclusive, as are --sync and --async.
  The body is wrapped as { "input": <json> } and POSTed to the endpoint's
  runsync (or run, with --async) route on the data plane.

## Examples

```
# Run a synchronous job with inline input
$ rp serverless run end_abc --input '{"prompt":"hi"}'

# Submit a job from a file and return immediately
$ rp serverless run end_abc --input-file job.json --async
```

**API:** `POST /v2/{id}/runsync  (or /run with --async)`

