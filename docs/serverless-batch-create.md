# rp serverless batch create
Create a new DRAFT batch (beta).

```
rp serverless batch create <endpoint> [--input '<json>']… [--input-file <path|->] [--json]
```

## Arguments

```
  <endpoint>       endpoint id — from `rp serverless list`
```

## Options

```
  --input '<json>' one request's input object; repeatable, each occurrence
                   appends one request (must be a single JSON value)
  --input-file <path|->
                   a JSON array of input objects; `-` reads stdin. Combined
                   with --input, file items come first
  --json           print the raw API response
```

## Notes
  The request body is a top-level JSON array; without --input/--input-file an
  empty array is sent. The new batch id is printed on stdout (confirmation on
  stderr), so the id composes into add/finalize. The batch stays DRAFT —
  nothing processes until `batch finalize`.

## Examples

```
# Create a batch with two requests
$ rp serverless batch create end_abc --input '{"text":"a"}' --input '{"text":"b"}'
```

**API:** `POST /v2/{endpoint_id}/batch`

