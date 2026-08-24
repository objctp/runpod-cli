# rp registry delete
Delete a registry credential.

```
rp registry delete <id>
```

## Arguments

```
  <id>             credential id — from `rp registry list`
```

## Notes
  Deletion is irreversible; pods or endpoints still referencing the credential
  will fail to pull.

**API:** `DELETE /v2/registries/{id}`

