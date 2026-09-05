# rp cost-center
Client-side cost centers: named buckets for per-project spend.
Runpod's own Cost Centers are console-only (no v2 REST or GraphQL surface),
so the tagging lives in a per-user state file and only the spend roll-up is
remote, reusing the per-resource billing endpoints behind `rp billing`.
Every resource sits in exactly one bucket; untagged resources are
"Uncategorized", matching the console. Because the tagging is local, it
survives a resource's deletion — a bucket's spend history keeps resolving by
id after the API-side object is gone, which the live lists no longer show.

```
rp cost-center <verb> [flags]
```

## Commands

- [`rp cost-center create`](cost-center-create.md) — Create a cost center: a named bucket for tagging resources.
- [`rp cost-center list`](cost-center-list.md) — List cost centers: name, note, and how many resources each one tags.
- [`rp cost-center assign`](cost-center-assign.md) — Tag resources to a cost center, moving them out of any previous one.
- [`rp cost-center unassign`](cost-center-unassign.md) — Remove resources from every cost center (they become Uncategorized).
- [`rp cost-center delete`](cost-center-delete.md) — Delete a cost center; its resources return to the untagged pool.
- [`rp cost-center spend`](cost-center-spend.md) — Report spend per cost center, rolled up from the billing endpoints.
