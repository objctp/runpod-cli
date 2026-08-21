# rp pod logs
Stream a pod's container and system logs live.

```
rp pod logs <id> [--source container|system] [--tail N]
                   [--since <rfc3339>] [--last-event-id <ts>]
```

## ARGUMENTS

```
  <id>                      pod id — from `rp pod list`
```

## OPTIONS

```
  --source container|system restrict the stream; omit for both
  --tail N                  historical lines to backfill (default: 100,
                            maximum 5000); 0 streams live with no backfill
  --since <rfc3339>         resume from a timestamp instead of backfilling
  --last-event-id <ts>      SSE reconnect cursor emitted by this endpoint
```

## NOTES
  The stream is Server-Sent Events written raw to stdout, so it pipes and
  redirects cleanly and there is no --json. Ctrl-C ends it.
  The three resume flags have a precedence: --last-event-id beats --since,
  which beats --tail. Setting a lower-precedence flag alongside a higher one
  has no effect.
  container is the container's stdout and stderr; system is the host
  lifecycle log, which is where pull failures and OOM kills appear.

## EXAMPLES

```
  rp pod logs pod_abc123 --tail 0
  rp pod logs pod_abc123 --source system --tail 500
```

**API:** `GET /v2/pods/{id}/logs`

