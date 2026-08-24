# rp template delete
Delete a template permanently.

```
rp template delete <id>
```

## Arguments

```
  <id>  template id — from `rp template list`
```

## Notes
  Deletion is irreversible and there is no confirmation prompt.
  Nothing built from the template goes with it: `rp pod create --template`
  and the serverless create paths copy the container config at create time,
  so running pods and endpoints keep their own copy.

**API:** `DELETE /v2/templates/{id}`

