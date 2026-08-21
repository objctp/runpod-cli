# rp cluster delete
Delete a cluster and tear down its member pods.

```
rp cluster delete <id>
```

## ARGUMENTS

```
  <id>             cluster id — from `rp cluster list`
```

## NOTES
  Deletion is irreversible; every member pod is destroyed with the cluster.

**API:** `DELETE /v2/clusters/{id}`

