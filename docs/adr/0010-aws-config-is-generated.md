# ~/.aws/config is generated from every overlay's aws/config

dotfiles is a base that overlays layer on: skill registries merge, every overlay's skills are
linked, every `git/gitconfig` is included, every `macos/Brewfile` applies. `aws/config` was the
exception. `~/.aws/config` was a link ([0001](0001-symlinks-not-copies.md)), a link has one
target, and so one `aws/config` across the repo and the overlays was the rule and two was an
error. That held while one employer had AWS accounts. It broke with the second: a machine could
not list Kealu's overlay beside one that already shipped Texo's profiles, and a Kealu
`aws/config` in an overlay every machine lists would have broken the machines that list Texo's.

So `~/.aws/config` is now written, not linked: a header, then each source under a
`# from <path>` line, the repo first and then the overlays in the order `machine.local.psd1`
lists them, with LF line endings. The same section in two sources is an error naming both, and
nothing is written, since either answer would be a guess, as the same skill id in two registries
is.

A link to one file per source was ruled out by the AWS CLI itself: it reads one config file and
has no include directive. Setting `AWS_CONFIG_FILE` per shell would reach only the shells that set
it, and still names one file.

This gives up what 0001 was for, in this one file: an edit in the checkout is not live until the
next setup or sync writes it, and drift is a content comparison rather than a link target. A
change to a profile is rare, and the sync runs at logon and every four hours, so that is a small
price. The other cost is that the AWS CLI writes to its config itself (`aws configure sso`), and
through a link that edit used to land in the overlay's checkout. It now lands in the generated
file, and the header says the next sync replaces it. The sync backs an edited file up before
replacing it, by the same rule `ssh/authorized_keys`' copy on Windows follows: a file that opens
with dotfiles' header is dotfiles' own, anything else is someone's and is backed up first
([0003](0003-back-up-then-link.md)). That rule lives once per language, in
`powershell/generated-file.ps1` and `ai/helpers/aws-config.sh` with `move_aside` in
`ai/helpers/managed-link.sh`.

A link at `~/.aws/config` is what every machine had before this, and holds no content of its own,
so it is replaced without a backup. With no source left, the generated file is removed, and so is
a link to an `aws/config`.

`ssh/authorized_keys` keeps its single source: it decides who may log in, and nothing has needed
two.
