# rp registry delegations create
Link an ECR repository for credential-free private-image pulls.

```
rp registry delegations create --resource <ecr-arn> [--name <n>]
```

## Options

```
  --resource <ecr-arn>         the ECR repository ARN to delegate (required)
  --name <n>                   label for the delegation (optional; omitted
                               from the body when not given)
  --json                       print the raw API response
```

## Notes
  On success the new delegation id is printed; the name is optional and, when
  absent, is not sent in the request body.

**API:** `POST /v2/registries/delegations`

