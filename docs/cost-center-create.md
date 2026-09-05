# rp cost-center create
Create a cost center: a named bucket for tagging resources.

```
rp cost-center create <name> [--note <text>]
```

## Arguments

```
  <name>           cost center name; local to this machine
```

## Options

```
  --note <text>    free-text note shown by `rp cost-center list`
```

## Notes
  Runpod's own Cost Centers are console-only, so `rp` keeps its cost centers
  locally: the buckets and their resource tags live in a per-user state file
  and only the spend roll-up talks to the API. Creating is idempotent on the
  name — an existing center is reported, never modified; delete and re-create
  to change its note.

## Examples

```
# Create a bucket per client
$ rp cost-center create freelance --note "client work"

# Create one per project on a solo account
$ rp cost-center create rag-pipeline
```

**API:** `none (local state: $RP_CONFIG_HOME/cost-centers.json)`

