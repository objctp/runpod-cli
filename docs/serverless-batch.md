# rp serverless batch
Submit large sets of inference requests to an endpoint as one managed batch (beta).

```
rp serverless batch <verb> [flags]
```

## Notes
  A batch is endpoint-scoped and rides the control plane (unlike `run`,
  which targets the data plane). Lifecycle: DRAFT → FINALIZED →
  FAILED|CANCELLED — work starts only after `finalize`, there is no
  RUNNING/COMPLETED status, and completion is inferred when completed +
  failed counts equal the total. Batch workers are isolated from /run
  traffic, so a batch never delays interactive jobs. Batches are addressed
  by id (display names are not unique). Sub-verbs: list, create, add,
  remove, finalize, cancel, get, requests, update.

**API:** `/v2/{endpoint_id}/batch`

## Commands

- [`rp serverless batch list`](serverless-batch-list.md) — List an endpoint's batches, newest first (beta).
- [`rp serverless batch create`](serverless-batch-create.md) — Create a new DRAFT batch (beta).
- [`rp serverless batch add`](serverless-batch-add.md) — Append requests to a DRAFT batch (beta).
- [`rp serverless batch finalize`](serverless-batch-finalize.md) — Lock a DRAFT batch and make it eligible for execution (beta).
- [`rp serverless batch cancel`](serverless-batch-cancel.md) — Cancel a batch (beta).
- [`rp serverless batch remove`](serverless-batch-remove.md) — Remove one request from a DRAFT batch (beta).
- [`rp serverless batch get`](serverless-batch-get.md) — Show a batch's progress summary (beta).
- [`rp serverless batch requests`](serverless-batch-requests.md) — List a batch's child requests with per-request status and results (beta).
- [`rp serverless batch update`](serverless-batch-update.md) — Rename a batch (beta).
