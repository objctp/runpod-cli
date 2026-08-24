# rp hub search
Search Hub listings by keyword.

```
rp hub search <query> [--json]
```

## Arguments

```
  <query>  search text; quote anything with spaces
```

## Options

```
  --json   print the raw listings array
```

## Notes
  The table shows the listing id, title, owner and type. That id is what
  `rp hub get` and `rp serverless create --hub-id` take.
  Results are capped at 20 and the cap is not exposed as a flag, so narrow
  the query rather than paging.
  The text goes to the Hub as its own searchQuery input, so the ordering is
  the marketplace's ranking, not a substring match the CLI performs.
  A query matching nothing prints just the header row.

## Examples

```
# Search the Hub for Stable Diffusion listings
$ rp hub search "stable diffusion"

# Search the Hub for Whisper listings
$ rp hub search whisper
```

**API:** `GraphQL listings(input: { searchQuery, limit })  (NO-V2-EQUIVALENT)`

