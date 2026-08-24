# rp auth login
Store a Runpod API key as an account (additive — does not replace others).
Login marks it active; the key then loads automatically on every `rp` call.

```
rp auth login [--name <n>] [--api-key <k>] [--from-runpodctl] [--s3-access-key <k>] [--s3-secret-key <k>]
```

## Options

```
  --name <n>            account name (default: "default")
  --api-key <k>         API key to store (non-interactive)
  --from-runpodctl      import the API key from runpodctl's ~/.runpod/config.toml
  --s3-access-key <k>   S3 access key (optional, for `rp volume sync`)
  --s3-secret-key <k>   S3 secret key (optional)
```

## Notes
  With no flags, prompts interactively at a terminal (input hidden), or reads
  the API key from the first stdin line when piped. If runpodctl's config holds
  a key, interactive login offers to import it; pass `--from-runpodctl` to take
  it without prompting. An explicit `--api-key` always wins. Stored unquoted at
  $RP_CONFIG_HOME/credentials.d/<name> (mode 600, dir 700); other lines there
  are preserved. The API key is the only auth Runpod supports — no OAuth.
