# How-to: skip TLS verification from inside a pod with a limited CA bundle

This is a worked task for running `rp` from inside a RunPod pod whose CA bundle
cannot validate api.runpod.io, so curl fails with "certificate signed by unknown
authority". The reference page (`rp doc`) documents every flag; this page shows
how to relax the certificate-chain check safely.

Goal: reach the RunPod API over an already-encrypted `https://` link when the
local trust store is incomplete, without reconfiguring the system CA bundle.

## Steps

```
$ RP_INSECURE_TLS=1 rp pod list
$ rp --insecure pod list
$ rp -k pod list
```

All three are equivalent: the environment variable `RP_INSECURE_TLS=1`, the
`--insecure` flag, and the short `-k` alias. The toggle passes `curl -k`, so the
link stays encrypted but the server identity is NOT authenticated. Use it only
when you trust the network path.

## Notes

- Applies to all three planes. The REST control plane, the serverless data plane
  (`api.runpod.ai`), and GraphQL all route through the same curl seam, so one
  setting covers every `rp` call.
- A one-time warning is printed to stderr when the toggle is first used in a
  process.
- Do not confuse this with `RP_ALLOW_INSECURE_HTTP=1`. That variable permits
  *plaintext* `http://` transport and is intended for local or test setups only;
  it does not skip certificate checks. `RP_INSECURE_TLS` / `--insecure` only
  relaxes the certificate chain over an already-encrypted `https://` link and
  never permits plaintext.
