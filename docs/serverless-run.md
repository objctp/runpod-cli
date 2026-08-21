# rp serverless run
Submit a job to a deployed endpoint on the data plane.

```
rp serverless run <id> --input '<json>' | --input-file <path|->
                    [--sync|--async] [--timeout <s>] [--json]
```

## ARGUMENTS

```
  <id>             endpoint id — from `rp serverless list`
```

## OPTIONS

```
  --input '<json>'          job input as a JSON string
  --input-file <path|->     read job input from a file, or - for stdin
  --sync                    block until the job completes (default)
  --async                   queue and print the job id instead of waiting
  --timeout <s>             request timeout in seconds (default: 300)
  --json                    print the raw API response
```

## NOTES
  --input and --input-file are mutually exclusive, as are --sync and --async.
  The body is wrapped as { "input": <json> } and POSTed to the endpoint's
  runsync (or run, with --async) route on the data plane.

## EXAMPLES

```
  rp serverless run end_abc --input '{"prompt":"hi"}'
  rp serverless run end_abc --input-file job.json --async
```

**API:** `POST /v2/{id}/runsync  (or /run with --async)`

