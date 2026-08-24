# How-to: get the SSH connection line and runtime ports for a running pod

This is a worked task for reading the SSH address of a running pod. The reference
page (`rp doc ssh info`) documents the individual flags; this page shows the
call composed into a single workflow.

Goal: get the `ssh` connection line and the runtime ports for a pod that is
currently running, so you can reach it over SSH.

## Steps

1. Get the raw pod id. `rp ssh info` takes the id verbatim — it does **not**
   resolve pod names — so read it from `rp pod list` first:

   ```
   $ rp pod list
   ```

   The `ID` column (for example `rp_abc123`) is the value to pass in step 2.

2. Print the connection line. Pass that raw id to `rp ssh info`; it reads the
   pod over the REST v2 control plane and prints the `ssh` line:

   ```
   $ rp ssh info rp_abc123
   ssh root@57.1.2.3 -p 22981
   ```

   The login user defaults to `root` (Runpod official images run as root).

3. Set the user for a non-root image. Images that start as a non-root user need
   `--user` to match, otherwise the printed line fails with a permission error:

   ```
   $ rp ssh info rp_abc123 --user ubuntu
   ssh ubuntu@57.1.2.3 -p 22981
   ```

   The `--user` value is not validated against the pod; pass the user the image
   actually starts as.

4. See the full pod record. `--json` prints the entire pod object the line was
   derived from — useful for inspecting every runtime port:

   ```
   $ rp ssh info rp_abc123 --json
   ```

## Notes

- The connection line is built from the first runtime port whose `type` is
  `ssh` **or** `tcp`, in the order the API returns them. It does not
  guarantee an `ssh`-labelled port is preferred over a `tcp` one — whichever
  appears first in `runtime.ports` is used.
- A stopped pod has no runtime and prints `pod has no runtime (stopped?)` rather
  than failing; start the pod and ask again.
- A running pod that exposes no `ssh` or `tcp` port prints its available runtime
  ports instead of a connection line.
- Registering a key with `rp ssh-key add` is what makes the address reachable;
  `rp ssh info` only reports it.
- The call rides `GET /v2/pods/{id}` on the control plane (`api.runpod.io/v2`).
