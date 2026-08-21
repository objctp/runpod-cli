# rp hub get
Show one Hub listing: release, image and config.

```
rp hub get <listing-id> [--json]
```

## ARGUMENTS

```
  <listing-id>  listing id — from `rp hub search`
```

## OPTIONS

```
  --json        print the raw listing object
```

## NOTES
  The human view prints the title and repository, the listed release name
  and tag, the built image reference, and the listing's config blob.
  config is the deployment recipe `rp serverless create --hub-id` reads, so
  this verb is how you see what that command will build before running it.
  An unknown id is a not-found error rather than an empty record: the query
  answers null and the CLI exits on it.

**API:** `GraphQL listing(id)  (NO-V2-EQUIVALENT)`

