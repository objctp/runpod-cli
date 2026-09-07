# rp completion zsh
Print the zsh completion artefact to stdout.

```
rp completion zsh
```

## Notes
  The artefact registers itself via compdef, which needs compinit to have
  run — source it after compinit in ~/.zshrc:
    rp completion zsh > "${HOME}/.rp/completions/_rp"
  and add `source "${HOME}/.rp/completions/_rp"` to ~/.zshrc.

## Examples

```
$ rp completion zsh > "${HOME}/.rp/completions/_rp"
```
