# How-to: check your account balance and serverless billing usage

This is a worked task that spans two separate `rp` surfaces — the account model
and the billing commands. The reference pages (`rp doc account info`, `rp doc
billing serverless`) document the individual flags; this page shows the two
queries composed into a single "how much am I spending?" check.

Goal: from the terminal, see your current account balance and spend limits, then
drill into how much your serverless endpoints have cost over a window of time.

## Account balance and spend

`rp account info` (also the default for bare `rp account`) reads the GraphQL
`myself` query and prints the account-level money facts: the current balance,
the spend limit, and the live hourly spend rate.

```
$ rp account info
```

The fields shown are:

- **Balance** (`clientBalance`) — credit remaining on the account.
- **Spend limit** (`spendLimit`) — the ceiling enforced by Runpod.
- **Current spend / hr** (`currentSpendPerHr`) — the run-rate across everything
  live right now.

It also reports the account `id`, `email`, and the three low-balance /
stale-pod notification toggles. There is no API v2 equivalent for this data;
it is fetched exclusively from GraphQL, and the command warns on every call
that GraphQL retires in early 2027 — the surface moves to a v2 endpoint when
one exists.

## Serverless billing usage

`rp billing serverless` reports usage for your serverless endpoints. With no
arguments and no window flags it covers every endpoint you own, returning the
usage history the API holds:

```
$ rp billing serverless
```

Pass an endpoint id to scope the report to one endpoint:

```
$ rp billing serverless ep_xyz789
```

### Choosing a time window

Pick exactly one of the two window styles — they are mutually exclusive:

- **Relative:** `--last-n N` counts back the last N buckets from now.

  ```
  $ rp billing serverless --last-n 24 --bucket-size hour
  ```

- **Absolute:** `--start` / `--end` define an RFC3339 window (start inclusive,
  end exclusive).

  ```
  $ rp billing serverless --start 2026-08-01T00:00:00Z --end 2026-08-23T00:00:00Z --bucket-size day
  ```

`--bucket-size` accepts `hour`, `day`, `week`, `month`, or `year` and sets the
granularity of each record. Add `--json` to get the raw response instead of the
formatted table:

```
$ rp billing serverless ep_xyz789 --bucket-size day --json
```

The same window flags (`--last-n`, `--start/--end`, `--bucket-size`, `--json`)
apply to the other billing verbs — `all`, `pods`, `volumes`, `clusters`, and
`public-endpoints`.

## Accounts and multiple keys

Both commands respect the active account. If you manage more than one Runpod
account, switch first with `rp auth switch <name>`, or override a single call
with `RUNPOD_API_KEY=<key> rp billing serverless`. See
[Manage multiple accounts](multiple-accounts.md) for the full model.
