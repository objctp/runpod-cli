# rp api
Raw REST and data-plane call over rp's own transport.
This is the same transport every resource verb uses, exposed for scripting
and ad-hoc calls: it resolves the method, path, plane, body, and optional jq
filter, then delegates to rp::http or rp::http_api — all curl, auth, timeout
and error policy live in lib/transport.sh behind that seam. It prints the
response body, and dies on HTTP 400 or above with the API's own message.

```
rp api <METHOD> <path> [--body <json>] [--plane rest|api]
              [--jq <filter>] [--limit N] [--cursor <c>]
```

## ARGUMENTS

```
  <METHOD>          HTTP method: GET/POST/PUT/DELETE/... (case-insensitive)
  <path>            REST path under the plane base (a leading / is optional)
```

## OPTIONS

```
  --body <json>     request body; prefix with @ to read a file
  --plane rest|api  rest = control plane (default) | api = serverless data plane
  --jq <filter>     jq filter applied to the response (implies JSON output)
  --limit N         cap the number of (top-level-array) items returned
  --cursor <c>      opaque offset for the next page (pairs with --limit)
```

## EXAMPLES

```
  rp api GET /pods
  rp api GET /pods --jq '.pods[] | .id'
  rp api POST /pods --body '{"name":"x","image":"y"}'
  rp api POST /$id/runsync --plane api --body '@job.json'
```

**API:** `raw call over rp::api_call — no single endpoint; the method and path`

     decide the route (control plane /v2 or data plane /v2).
