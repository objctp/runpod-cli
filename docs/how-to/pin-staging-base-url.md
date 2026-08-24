# How-to: pin the CLI to a staging or alternate REST v2 base URL

This is a worked task for redirecting `rp`'s network traffic to a staging host
or any alternate base URL while testing. The reference page (`rp doc api`)
documents the transport; this page shows how the base-URL overrides are set.

Goal: send control-plane, serverless data-plane, and GraphQL requests to a
non-production host without editing any script or source file.

## Steps

The CLI reads three environment variables at call time, one per transport
plane. Set whichever apply to your test; all three default to RunPod's
production hosts when unset.

Pin the control-plane REST v2 base (pods, volumes, serverless, registries, …):

```
$ RP_REST_BASE=https://staging.runpod.io/v2 rp pod list
```

Pin the serverless data plane (job submission to a deployed endpoint):

```
$ RP_API_BASE=https://staging.runpod.ai/v2 rp serverless run <endpoint-id> --input '{...}'
```

Pin the GraphQL plane (account, Hub, SSH keys, datacentre stock):

```
$ RP_GRAPHQL_URL=https://staging.runpod.io/graphql rp account
```

Redirect all traffic to one staging host by exporting all three in a single shell:

```
$ export RP_REST_BASE=https://staging.runpod.io/v2
$ export RP_API_BASE=https://staging.runpod.ai/v2
$ export RP_GRAPHQL_URL=https://staging.runpod.io/graphql
$ rp pod list          # now hits staging for every plane
```

If the staging host speaks plaintext `http://` rather than `https://`, the CLI
refuses the transport by default. Opt out for that local or test setup only:

```
$ RP_ALLOW_INSECURE_HTTP=1 RP_REST_BASE=http://localhost:8080/v2 rp pod list
```

## Notes

- The overrides are environment-variable only. There is no command-line flag
  for them: they are resolved in `lib/common.sh` and consumed by the single
  curl seam in `lib/transport.sh`.
- To redirect the entire CLI to staging, set all three (`RP_REST_BASE`,
  `RP_API_BASE`, `RP_GRAPHQL_URL`). Setting only one leaves the other planes
  pointed at production.
- `RP_ALLOW_INSECURE_HTTP=1` is required only when a base URL uses `http://`; an
  `https://` staging host needs no extra flag. The guard exists because the API
  key and (on `rp registry create`) the registry password would otherwise cross
  the wire in cleartext.
- `RP_ALLOW_INSECURE_HTTP` is distinct from `--insecure` / `RP_INSECURE_TLS=1`:
  the latter only relaxes the TLS certificate chain check over an already-
  encrypted `https://` link, whereas the former permits plaintext transport.
