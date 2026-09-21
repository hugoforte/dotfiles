# Everything is a symlink, not a copy

Managed files are symlinked from the checkout to where the tool expects them, rather than copied
there by an installer. This is the decision the whole repo rests on: it means an edit in the
checkout is live in the same instant, with nothing to re-run, and it means "has this machine
drifted?" is answerable by reading a link target rather than by diffing content.

The cost is paid on Windows, where symlinks are privileged by default. Every machine must have
Developer Mode on, and `ai/install.sh` needs `MSYS=winsymlinks:nativestrict` or Git Bash silently
copies instead — a failure mode that looks like success until the next edit does not propagate.

Copying was the obvious alternative and is what `aws-setup-profile` actually did until
hugoforte/dotfiles#6: it needs no privilege and no Developer Mode. It was rejected because a copy
goes stale silently. A copied file that has diverged is indistinguishable from one that has not
without comparing content, and the copy in `aws.ps1` was in fact quietly replacing a managed link
with a stale file.

One thing is deliberately not a link: `ai/claude/settings.json` is *merged* into
`~/.claude/settings.json`, because Claude Code writes to that file itself. See
[0002](0002-mklink-not-new-item.md) for how the links are made.
