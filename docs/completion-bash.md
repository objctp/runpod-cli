# rp completion bash
Print the bash completion artefact to stdout.

```
rp completion bash
```

## Notes
  Wire it into the current shell with: source <(rp completion bash)
  To keep it, add that source line (or the installer's equivalent) to
  ~/.bashrc. The artefact is bash 3.2+ — it runs in the INTERACTIVE shell,
  which may be older than the Bash 5.1 rp itself requires.

## Examples

```
$ rp completion bash >> ~/.bashrc
```
