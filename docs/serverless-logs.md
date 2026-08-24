# rp serverless logs
Stream one worker's container and system logs live.

```
rp serverless logs <id> --worker <workerId>
                    [--source container|system] [--tail N]
                    [--since <rfc3339>] [--last-event-id <ts>]
```

## Arguments

```
  <id>                      endpoint id — from `rp serverless list`
```

## Options

```
  --worker <workerId>       worker id (from `rp serverless workers <id>`);
                            required
  --source container|system restrict the stream; omit for both
  --tail N                  historical lines to backfill (default: 100,
                            maximum 5000); 0 streams live with no backfill
  --since <rfc3339>         resume from a timestamp instead of backfilling
  --last-event-id <ts>      SSE reconnect cursor emitted by this endpoint
```

## Notes
  The stream is Server-Sent Events written raw to stdout (no --json); Ctrl-C
  ends it. The three resume flags follow --last-event-id > --since > --tail
  precedence.
  container is the worker's stdout/stderr; system is the host lifecycle log.

**API:** `GET /v2/serverless/{id}/workers/{workerId}/logs`

