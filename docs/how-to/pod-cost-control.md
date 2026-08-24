# How-to: stop and start a pod to control spend without losing its disks

This is a worked task for the most common cost-control flow. The reference
pages (`rp doc pod stop`, `rp doc pod start`, `rp doc pod get`) document the
individual flags; this page shows them composed into a pause-and-resume
cycle.

Goal: stop paying for a pod's GPU while keeping its disks and data, then
bring it back exactly as it was.

## Steps

1. Find the pod. The verbs take the pod **by id**, so read it from the list
   first:

   ```
   $ rp pod list
   ```

2. Stop the pod. The GPU (or CPU) charge ceases; the disks are kept:

   ```
   $ rp pod stop rp_abc123
   ```

   Stopping is asynchronous — the command returns once the transition is
   accepted, not once the pod is stopped. Poll with:

   ```
   $ rp pod get rp_abc123
   ```

3. Start it again when you need it:

   ```
   $ rp pod start rp_abc123
   ```

   Starting is asynchronous too, and can fail later if the pod's GPU type is
   out of stock in its datacentre — poll `rp pod get` and check stock with
   `rp stock gpu` if the pod stays down.

## Notes

- A stopped pod still bills for its **storage**; only the compute charge
  ceases. Use `rp pod delete <id>` to stop paying entirely.
- A locked pod refuses to stop. Unlock it first with
  `rp pod update <id> --locked false`.
- `rp pod restart <id>` recreates the container in one step — anything
  written outside `/workspace` or a network volume is lost. A stop/start
  cycle preserves disk state; a restart does not promise to.
- To tear everything down rather than pause, see
  [Tear down endpoints, pods, and volumes in the right order](teardown-order.md).
