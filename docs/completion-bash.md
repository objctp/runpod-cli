# rp completion bash
Print the bash completion bootstrap to stdout.

```
rp completion bash
```

## Notes
  The output is a tiny lazy bootstrap: it registers a stub and sources the
  full generated grammar only on the first `rp` TAB, so it never slows an
  idle shell. Write it to a file and source that — a process substitution
  would not resolve the grammar path:
    rp completion bash > ~/.rp/completions/rp.lazy.bash
    echo '[[ $- == *i* ]] && source ~/.rp/completions/rp.lazy.bash' >> ~/.bashrc
  The installer does this for you. The artefact is bash 3.2+ — it runs in
  the INTERACTIVE shell, which may be older than the Bash 5.1 rp requires.

## Examples

```
$ rp completion bash > ~/.rp/completions/rp.lazy.bash
```
