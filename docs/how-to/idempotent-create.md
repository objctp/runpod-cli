# How-to: make resource creation idempotent so re-running returns the existing resource

This is a worked task. The reference pages (`rp doc <resource> create`) document the
individual flags; this page shows how to write a provisioning block you can run
more than once without duplicating resources, and which resources that applies to.

Goal: a re-runnable provisioning script — volumes, clusters, serverless endpoints —
that leaves what already exists in place and creates only what is missing.

## Why idempotency matters here

Several `rp create` verbs are *idempotent by name*. With a non-empty `--name`
and no `--force`, the CLI resolves the name to an id first and, if a match
exists, prints that id and skips the POST instead of creating a duplicate. The
shared seam is `rp::resource_create` (`lib/resource.sh`): it only POSTs when
the name is empty, `--force` is given, or no record matches.

That means a block you run once, then run again after a failure or a clean
checkout, returns what it already made — as long as you keep the same `--name`
and leave `--force` off.

## Resources that are idempotent by name

- `rp volume create --name <n>` — skips the POST if a volume of that name
  exists.
- `rp serverless create --name <n>` — returns the existing endpoint;
  `--force` skips the name check (both the `--template` and `--hub-id`
  paths).
- `rp cluster create --name <n>` — returns the existing fleet; `--force`
  sends the request regardless.
- `rp template create --name <n>` — returns the existing template; `--force`
  creates even when the name is taken.

## Resources that are NOT idempotent

- A standard `rp pod create` passes an empty name into the create seam, so
  the name check never runs; re-running always creates a new pod, and
  `--force` changes nothing. The exception is the spot path
  (`--interruptible` / `--bid-per-gpu`): it honours the name gate, so a
  re-run with the same `--name` is a no-op.
- `rp registry create` takes a `--name` but does not gate on it — it always
  POSTs a new credential set.

For non-spot pods, guard the create with a pre-check (for example,
`rp pod list --json --jq` to see whether the name is already present) before
you create.

## Steps

1. Give every re-runnable resource a stable `--name`, and never pass `--force`
   unless you deliberately want a collision:

   ```
   $ rp volume create --name hf-cache --size 100 --dc EU-RO-1        # no-op if exists
   $ rp cluster create --name tr-1 --type TRAINING \
       --gpu "NVIDIA L4" --pod-count 2 \
       --network-volume-id "$(rp volume create --name hf-cache --size 100 --dc EU-RO-1)" \
       --volume-path /runpod-volume                                  # no-op if exists
   $ rp serverless create --name my-endpoint --hub-id <id> \
       --network-volume hf-cache --gpus-from-volume hf-cache \
       --workers-min 0 --workers-max 3                               # no-op if exists
   ```

   Each line prints the existing id on a re-run rather than creating a duplicate.

2. Capture the id when you need it downstream — the id is printed on stdout and the
   confirmation message on stderr, so `id=$(rp volume create …)` keeps just the id:

   ```
   $ vol=$(rp volume create --name hf-cache --size 100 --dc EU-RO-1)
   $ rp cluster create --name tr-1 --type TRAINING --gpu "NVIDIA L4" \
       --network-volume-id "$vol" --volume-path /runpod-volume
   ```

3. Guard standard pod creation (the non-idempotent case) with a name lookup
   first:

   ```
   $ if ! rp pod list --json --jq '.[] | select(.name == "trainer")' | grep -q .; then
   >   rp pod create --name trainer --image runpod/pytorch:2.2.0 \
   >     --gpu "NVIDIA L4" --container-disk-gb 50
   > fi
   ```

## Notes

- Idempotency is name-based and resolved against your account, so two different
  accounts can each own a resource of the same name; switch accounts with
  `rp auth use` if a re-run unexpectedly creates a duplicate.
- `--force` is the only escape hatch: on an idempotent resource it bypasses the
  name check and lets you create a second resource sharing the name. Reserve it
  for when you genuinely want that.
- The name check is a list-then-filter (`rp::resource_id`), so it reflects what
  the API already has — a resource created out of band still counts as "existing".
