# rp serverless
Serverless endpoints: deploy, scale, inspect and invoke.
An endpoint runs a container image on demand behind a queue or a load
balancer, scaling a pool of workers between a minimum and a maximum. The
image comes from a template or a Hub listing rather than from flags, and jobs
are submitted on the data plane with `rp serverless run`.

```
rp serverless <verb> [flags]
```

## Commands

- [`rp serverless batch`](serverless-batch.md) — Submit large sets of inference requests to an endpoint as one managed batch (beta).
- [`rp serverless create`](serverless-create.md) — Create a serverless endpoint from a template or a Hub listing.
- [`rp serverless list`](serverless-list.md) — List your endpoints: id, name, worker bounds and idle timeout.
- [`rp serverless get`](serverless-get.md) — Show one endpoint's full record and scaling config.
- [`rp serverless update`](serverless-update.md) — Change an endpoint's workers, GPU pool, registry, template, name, or scaling.
- [`rp serverless delete`](serverless-delete.md) — Delete a serverless endpoint permanently.
- [`rp serverless scale`](serverless-scale.md) — Set an endpoint's worker bounds and idle timeout in one call.
- [`rp serverless workers`](serverless-workers.md) — Show an endpoint's live workers: ids, states, placement, versions.
- [`rp serverless releases`](serverless-releases.md) — Show an endpoint's release history and rollout.
- [`rp serverless logs`](serverless-logs.md) — Stream one worker's container and system logs live.
- [`rp serverless run`](serverless-run.md) — Submit a job to a deployed endpoint on the data plane.
- [`rp serverless status`](serverless-status.md) — Check the status of a job submitted earlier on a deployed endpoint.
- [`rp serverless health`](serverless-health.md) — Show a deployed endpoint's operational health: worker and job counts.
