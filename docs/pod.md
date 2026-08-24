# rp pod
On-demand GPU and CPU pod lifecycle.
A pod is a single container billed per second, built from an image (or from a
template's container config) and addressed by id. Every pod is either a GPU
pod or a CPU pod, never both. Storage is one host-local persistent volume or
one network volume, and the choice is fixed at create time.

```
rp pod <verb> [flags]
```

## Commands

- [`rp pod create`](pod-create.md) — Create a pod from an image, optionally seeded by a template.
- [`rp pod list`](pod-list.md) — List your pods as a table: id, name, image, status, cost.
- [`rp pod get`](pod-get.md) — Show one pod's full record, including runtime ports and utilisation.
- [`rp pod update`](pod-update.md) — Change a pod's configuration in place, restarting it.
- [`rp pod delete`](pod-delete.md) — Terminate a pod permanently.
- [`rp pod start`](pod-start.md) — Start a stopped pod.
- [`rp pod stop`](pod-stop.md) — Stop a running pod, keeping its disks.
- [`rp pod reset`](pod-reset.md) — Deprecated: alias for `restart` — v2 removed the reset action.
- [`rp pod restart`](pod-restart.md) — Restart a running pod.
- [`rp pod logs`](pod-logs.md) — Stream a pod's container and system logs live.
