# rp cost-center delete
Delete a cost center; its resources return to the untagged pool.

```
rp cost-center delete <name>
```

## Arguments

```
  <name>           cost center to remove
```

## Notes
  Mirrors the console: deleting a cost center does not touch the resources,
  it only removes the bucket, and previously tagged ids become Uncategorized.

**API:** `none (local state: $RP_CONFIG_HOME/cost-centers.json)`

