# How-to: tear down endpoints, pods, and volumes in the right order

This is a worked task where sequencing is the whole point. The reference
pages (`rp doc <resource> delete`) document the individual flags; this page
shows the dependency-aware order that avoids "cannot delete" errors and
accidental data loss.

Goal: remove a setup cleanly — serverless endpoints, pods or clusters, then
network volumes — without orphans and without deleting a volume that still
has a tenant.

## Steps

1. Delete the serverless endpoints first, so their workers release any
   network-volume mounts. Resolve each endpoint by id from the list:

   ```
   $ rp serverless list
   $ rp serverless delete end_abc123
   ```

2. Delete the pods — or the cluster, which tears down its member pods with
   it. Deleting a cluster destroys every member irreversibly:

   ```
   $ rp pod list
   $ rp pod delete rp_abc123
   $ rp cluster list
   $ rp cluster delete cluster_abc123
   ```

3. Delete the volumes last. A volume still mounted by a pod cannot be
   deleted — the command refuses until the tenant is gone (step 2 is what
   removes it):

   ```
   $ rp volume list
   $ rp volume delete vol_abc123
   ```

## Notes

- Deletion is irreversible at every layer: pods and clusters take their
   state with them, and a deleted volume takes its contents. There is no
   stop-and-keep state for volumes as there is for pods — if you want the
   data later, stop at step 2.
- `rp volume delete` prints a confirmation line and nothing else; there is
   no `--json` output to capture.
- The delete verbs take ids, not names. Each step's list command supports
   `--json --jq` if you want to script the resolution, e.g.
   `rp volume list --json --jq '.[] | select(.name=="hf-cache") | .id'`.
- A gentler pause — stop the pods, keep the volumes — is covered in
   [Stop and start a pod to control spend without losing its
   disks](pod-cost-control.md).
