# rp auth login
Store a RunPod API key as an account (additive — does not replace others) and
mark it active. The key loads automatically on every `rp` call thereafter.

```
rp auth login [--name <n>] [--api-key <k>] [--s3-access-key <k>] [--s3-secret-key <k>]
```

## OPTIONS

```
  --name <n>            account name (default: "default")
  --api-key <k>         API key to store (non-interactive)
  --s3-access-key <k>   S3 access key (optional, for `rp volume sync`)
  --s3-secret-key <k>   S3 secret key (optional)
```

## NOTES
  With no flags, prompts interactively at a terminal (input hidden), or reads
  the API key from the first stdin line when piped. Stored unquoted at
  $RP_CONFIG_HOME/credentials.d/<name> (mode 600, dir 700); other lines there
  are preserved. The API key is the only auth RunPod supports — no OAuth.
