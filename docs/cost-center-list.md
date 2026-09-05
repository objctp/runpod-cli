# rp cost-center list
List cost centers: name, note, and how many resources each one tags.

```
rp cost-center list [--json] [--jq <filter>]
```

## Options

```
  --json           print the rows as JSON
  --jq <filter>    jq filter applied to the rows array
```

## Notes
  The resource count covers tagged ids only. See which ids with --jq:
  `rp cost-center list --json` prints the rows; the ids themselves come from
  the spend breakdown (`rp cost-center spend <name> --json`).

**API:** `none (local state: $RP_CONFIG_HOME/cost-centers.json)`

