# A LaunchAgent syncs the Mac

A Mac keeps itself in line with the repo the way a Windows machine does, through a job that runs
`macos/sync.sh` at login and every 4 hours: a launchd **LaunchAgent**,
`com.hugoforte.dotfiles-sync`, installed by `macos/install-sync-agent.sh` into
`~/Library/LaunchAgents/`. It logs to `~/Library/Logs/dotfiles-sync.log`, where Console finds it.

A run pulls this repo and every overlay repo fast-forward only, then runs `macos/setup.sh`, so
the links, `~/.gitconfig-overlays` and `ai/install.sh` are re-applied on every run, then deploys
the skill secrets when `machine.local.psd1` declares `SearchRoots`. `brew bundle` runs only when
a Brewfile changed since the last bundle that succeeded, as `install-tools.ps1 -IfChanged` does:
a bundle is slow, and an unchanged Brewfile has nothing to add. A failed overlay pull or bundle
is logged and the rest of the run carries on, then the run exits 1.

cron was the alternative every Unix has. It was rejected because Apple deprecates it, runs it
without the user's session, and skips a run the machine slept through; launchd runs a missed
`StartInterval` job on wake and is how macOS expects a user's background job to be declared.
A LaunchDaemon was rejected too: it runs as root, and the sync writes into the user's home.

Two things differ from the Windows task and are deliberate. A LaunchAgent starts with
`PATH=/usr/bin:/bin:/usr/sbin:/sbin`, so `sync.sh` puts Homebrew on `PATH` itself rather than
relying on a shell profile. And launchd has no start delay like the task's two minutes after
logon, so the first run at login may find no network; its failed pull is logged, and the next
run, at most 4 hours later, catches up.
