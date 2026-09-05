# rp cost-center unassign
Remove resources from every cost center (they become Uncategorized).

```
rp cost-center unassign <id>…
```

## Arguments

```
  <id>…            one or more resource ids to untag
```

## Notes
  Unknown ids are ignored, so the verb is safe to re-run.

**API:** `none (local state: $RP_CONFIG_HOME/cost-centers.json)`

