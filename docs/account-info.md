# rp account info
Show your account balance and spend.

```
rp account [info]
```

## OPTIONS

```
  --json  print the raw GraphQL response
```

## NOTES
  Backed by the GraphQL `myself` query — there is no API v2 equivalent in the
  current v2 spec (confirmed against /v2/openapi.json: no user/account read
  endpoint exists; only /v2/account/ssh-keys). Runs until the early-2027
  GraphQL retirement; revisit if Runpod ships a v2 account endpoint.

**API:** `GraphQL `myself { id email clientBalance spendLimit currentSpendPerHr`

     notifyPodsStale notifyPodsGeneral notifyLowBalance }` (NO-V2-EQUIVALENT)
