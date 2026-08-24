# How-to: list and manage delegated AWS ECR registry access

This is a worked task that shows how to list, link, and revoke AWS Elastic Container Registry (ECR) delegations through `rp`. The reference page (`rp doc registry delegations`) documents the individual flags; this page composes the three verbs into a daily workflow.

## Steps

1. **List your ECR delegations.** This shows each delegation's id, name, repository, tag, AWS region, and creation time:

   ```
   $ rp registry delegations list
   ```

   Pass `--json` to receive the delegations array (unwrapped from the API
   envelope) instead of the table:

   ```
   $ rp registry delegations list --json
   ```

2. **Link an ECR repository (create a delegation).** Provide the ECR repository ARN with `--resource`; the optional `--name` labels the entry:

   ```
   $ rp registry delegations create --resource arn:aws:ecr:us-east-1:123456789012:repository/my-repo
   $ rp registry delegations create --resource arn:aws:ecr:us-east-1:123456789012:repository/my-repo --name training-images
   ```

   On success the new delegation id is printed. `--resource` is required; `--name` is optional and omitted from the request body when absent.

3. **Revoke a delegation.** Use the id from `rp registry delegations list`:

   ```
   $ rp registry delegations revoke clabcd1234
   ```

   Removal is irreversible; images from that repository will then need a stored credential to be pulled again.

## Notes

- A delegation **links an AWS ECR repository to your Runpod account** so private images can be pulled without a stored registry credential. It does **not** grant registry access to another Runpod user — each delegation references an AWS ECR ARN, never another user or account.
- There is **no prerequisite**: you do not need a prior registry auth entry, nor another user's cooperation, to create a delegation.
- All three verbs ride the control-plane **REST API v2** (`api.runpod.io/v2`).
- `rp registry` (the bare resource) manages stored *credentials* (username/password) and is a separate surface from `delegations`; do not confuse the two.
- Revocation is irreversible.
