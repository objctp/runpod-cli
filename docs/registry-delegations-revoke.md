# rp registry delegations revoke
Remove an ECR access delegation.

```
rp registry delegations revoke <id>
```

## ARGUMENTS

```
  <id>             delegation id — from `rp registry delegations list`
```

## NOTES
  Removal is irreversible; images from that repository will then need a stored
  credential to be pulled again.

**API:** `DELETE /v2/registries/delegations/{id}`

