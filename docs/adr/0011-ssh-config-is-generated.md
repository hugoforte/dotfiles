# ~/.ssh/config is generated from every overlay's ssh/config

An overlay may need to add to the ssh client's configuration: Kealu's SSH installer puts its host
config in `~/.ssh/config.d/` and relies on `~/.ssh/config` holding `Include ~/.ssh/config.d/*`.
Finding no `~/.ssh/config`, it leaves a `~/.ssh/config.new` beside it, which ssh never reads. More
than one overlay may ship such a line, so `~/.ssh/config` is written the way `~/.aws/config` is
([0010](0010-aws-config-is-generated.md)), not linked: `macos/setup.sh`, and so the sync, merges
every `ssh/config` among this repo and the listed overlays, the repo first and then the overlays in
the order `machine.local.psd1` lists them, each under a `# from <path>` line. The repo is a root as
it is for `aws/config`, though it ships none. ssh keeps the first value it finds for a setting, so
when two sources both give one, the earlier wins, and the overlays' order is the precedence.

Unlike the AWS CLI, ssh has `Include`, and a link to each source's file through one `Include` per
overlay was the alternative. It was rejected because the line that names those files would itself
be generated, so the file is generated either way, and a merged file shows what ssh reads in one
place. Nothing is an error the way the same AWS section in two sources is: two `Host` blocks for
one name are how ssh_config layers settings.

In ssh_config a line belongs to the `Host` or `Match` block above it, `Include` too. A source
that ends inside a `Host foo` block would make the next source's lines apply to `foo` alone, so
each source opens with `Match all`, right after its `# from` line, which puts it back in global
scope.

Ownership is 0010's header and checksum, and the code is shared: `ai/helpers/generated-file.sh`
holds what `aws-config.sh` did alone before, and `ssh-config.sh` uses it. A file dotfiles did not
write, or one edited since, is backed up before it is replaced
([0003](0003-back-up-then-link.md)). So is a link, unlike at `~/.aws/config`: dotfiles never
linked `~/.ssh/config`, so a link there is its owner's, pointing at config kept elsewhere, and
setup says where it pointed. Setup sets `~/.ssh` to
mode 700 and the file to 600 on every run. `--check` compares content only, as for `aws/config`,
since the suite also runs under Git Bash, which holds no Unix modes.

When no listed overlay ships `ssh/config`, a `~/.ssh/config` of anyone else's is left alone, and
setup says it skipped. A file dotfiles wrote and nobody edited since is removed, as 0010 removes
its own `~/.aws/config`: every line in it came from overlays the machine no longer lists, and
leaving it would keep their hosts configured with nothing to say where they came from. Removing
it loses nothing, since an edit makes the file someone's own and keeps it. Unlike `~/.aws/config`,
a link left dangling at `~/.ssh/config` stays, because dotfiles never made one.

This is macOS only. Windows generates `~/.aws/config` in `powershell/aws-config.ps1`, but the
machines that need an `ssh/config` are Macs, and there is no Linux entry point; `setup.ps1` gets
the same when a Windows machine needs it.
