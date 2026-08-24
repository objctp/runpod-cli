# How-to: call a raw REST v2 route that has no typed command

This is a worked task for reaching a RunPod v2 endpoint that `rp` does not yet
wrap in a typed verb (`rp pod`, `rp serverless`, …). The reference page
(`rp doc api`) documents the flags; this page shows the transport composed
into a real call.

Goal: hit any control-plane or serverless route directly — list, create,
patch, or restart — reusing `rp`'s auth, timeouts, and error handling instead
of reaching for `curl` by hand.

## Steps

1. Make a first call. The command prints the raw response body to stdout and
   exits non-zero on HTTP ≥ 400, surfacing the API's own error message — the
   same die-on-4xx policy every typed verb uses:

   ```
   $ rp api GET /pods                  # list every pod on the active account
   $ rp api GET /pods/<id>             # fetch one pod by id
   ```

2. Send a body to create or act on a resource. Inline JSON works, or prefix
   with `@` to read the body from a file:

   ```
   $ rp api POST /pods --body '{"name":"x","image":"y"}'
   $ rp api POST /pods --body @payload.json
   $ rp api POST /pods/<id>/action --body '{"action":"restart"}'
   ```

   Secrets stay off process listings twice over: the API key crosses as a
   header written to a temp file (`curl -H @file`), and the body travels
   through its own temp file (`--data @file`) — neither ever appears on
   argv, so nothing leaks into `ps`.

3. Choose the plane when the route is not on the control plane. `--plane
   rest` (the default) covers CRUD on pods, volumes, endpoints, registries;
   `--plane api` addresses the serverless data plane for job submission to a
   deployed endpoint:

   ```
   $ rp api POST /<endpoint-id>/runsync --plane api --body '{"input":{"x":1}}'
   ```

## Notes

- `--jq <filter>` runs a `jq` expression over the body (implies JSON
  output):

  ```
  $ rp api GET /pods --jq '.pods[] | .id'
  ```

  Note that `jq`'s `env` exposes the whole shell environment, including
  `RUNPOD_API_KEY` — never run `rp api … --jq 'env'` on a shared terminal
  or in logs you do not control.
- `--limit N` and `--cursor <c>` slice a **top-level array** only. Most list
  routes (e.g. `GET /pods`) return an object wrapper — `{"pods": […]}` —
  which pagination cannot slice, and pagination runs before `--jq`, so a
  filter cannot unwrap it either. Use the typed verb's `--limit` for those
  (it unwraps first) and reserve `--limit`/`--cursor` for bare-array routes.
- `rp api` honours the same resolution order as every other verb, so you can
  scope a raw call to a specific account:

  ```
  $ rp api GET /pods --account personal
  $ RUNPOD_API_KEY=<key> rp api GET /pods
  ```

- Method is case-insensitive (`get` / `GET` both work).
- Errors are fatal with distinct exit codes: HTTP 401/403 exits 3, 404 exits
  4, any other ≥ 400 exits 1 — and the API's `error`/`message` field is
  printed — so scripts can rely on the exit code.
