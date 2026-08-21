# rp volume get
Show one network volume's full record.

```
rp volume get <id> [--jq <filter>] [--json]
```

## ARGUMENTS

```
  <id>           network volume id — from `rp volume list`
```

## OPTIONS

```
  --jq <filter>  jq filter applied to the record
  --json         print the raw API response instead of pretty JSON
```

## NOTES
  This verb takes an id, not a name. The data-plane verbs (`sync`, `ls`,
  `gpus`) are the ones that accept a name and resolve it for you.
  The record carries the storage tier chosen at create, which no other verb
  can change.

**API:** `GET /v2/network-volumes/{id}`

