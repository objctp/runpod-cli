# How-to: submit a job to a serverless endpoint with a JSON input payload

You have a deployed serverless endpoint and want to run a job against it with a
JSON input. This guide covers the three ways to supply that payload. For the
full flag reference and worked examples, run `rp doc serverless run` in the
terminal — this page is a quick task guide, not the command manual.

## Steps

Identify the endpoint by its id (for example `end_abc`, from
`rp serverless list`). Then choose one of the three input forms.

1. Inline JSON string — pass the payload directly with `--input`:

   ```
   $ rp serverless run end_abc --input '{"prompt":"hi"}'
   ```

2. JSON file — read the payload from a file with `--input-file`:

   ```
   $ rp serverless run end_abc --input-file job.json
   ```

3. Standard input — pass `-` to `--input-file` to read from a pipe:

   ```
   $ cat job.json | rp serverless run end_abc --input-file -
   ```

In every case the payload is wrapped as `{"input": <json>}` before it is sent,
so the JSON you supply is the value of the `input` field.

## Notes

- **Endpoint by id.** `rp serverless run` takes the endpoint id as a
  positional argument and validates its format; it does not resolve endpoint
  names, so supply the id (e.g. `end_abc`), not a friendly name.
- **Sync vs async.** By default the call is synchronous (`--sync`): it blocks
  until the job finishes and prints the result. Pass `--async` to queue the
  job and return immediately with the job id instead. `--sync` and `--async`
  are mutually exclusive, and `--input` / `--input-file` are mutually
  exclusive. To drive an async job to completion, see
  [Submit a serverless job asynchronously and poll it to
  completion](serverless-async-poll.md).
- **Timeout and JSON.** `--timeout <s>` sets the request timeout in seconds
  (default `300`). Add `--json` to print the raw API response instead of the
  human-readable rendering.
- **Data plane.** The request rides the serverless data plane
  (`https://api.runpod.ai/v2`), not the control-plane REST. It is a `POST` to
  `/{id}/runsync` in sync mode, or `/{id}/run` with `--async`.
