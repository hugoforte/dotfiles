# The tools and programs a machine of mine needs. Read by install-tools.ps1.
#
# Every entry is a hashtable:
#
#   Id          winget package id, npm package name, GitHub owner/repo, or a slug for a manual step
#   Source      'winget' | 'npm' | 'github-release' | 'manual'
#   Unattended  $false to keep sync.ps1 from installing it behind your back (default $true)
#   Optional    the name of the option this entry belongs to; omit for every machine
#   Note        what it is, or - for manual entries - what you have to do
#   Url         optional, for manual entries that need a page
#
# A 'github-release' entry installs its repo's latest release, and also needs:
#   Asset        -like pattern naming the installer among the release's assets
#   InstallArgs  arguments for a silent install
#   Present      -like pattern for its display name under Installed apps, which is how it is found;
#                make it tell this build from any other of the same app
#
# Entries install only when missing; nothing here is ever upgraded or uninstalled by the
# installer. Add a tool, push, and every machine picks it up on its next sync.
#
# Every machine gets every entry, except optional ones: a machine opts into an option by listing
# its name under OptionalTools in ai/secrets/machine.local.psd1, and then gets every entry of
# that option, manual steps included.

@{
    Tools = @(

        # --- winget ------------------------------------------------------------------------

        @{ Id = 'jqlang.jq'
           Source = 'winget'
           Note = 'JSON processor; ai/install.sh needs it to merge Claude settings' }

        @{ Id = 'FiloSottile.age'
           Source = 'winget'
           Note = 'Encryption backend for the skill secrets' }

        @{ Id = 'SecretsOPerationS.SOPS'
           Source = 'winget'
           Note = 'Encrypts ai/secrets; deploy-secrets.ps1 refuses without it' }

        @{ Id = 'OpenJS.NodeJS'
           Source = 'winget'
           Unattended = $false
           Note = 'Runtime for every npm entry below. Not unattended: swapping the runtime under running node processes is the disruptive case this flag exists for' }

        # --- npm globals -------------------------------------------------------------------

        @{ Id = 'markdownlint-cli2'
           Source = 'npm'
           Note = 'Markdown linter. Use bin/md-lint, not the binary directly - it has no global config of its own' }

        @{ Id = '@anthropic-ai/claude-code'
           Source = 'npm'
           Note = 'Claude Code CLI' }

        @{ Id = '@openai/codex'
           Source = 'npm'
           Note = 'Codex CLI' }

        @{ Id = '@usebruno/cli'
           Source = 'npm'
           Note = 'Bruno API client CLI' }

        @{ Id = '@playwright/cli'
           Source = 'npm'
           Note = 'Browser automation any agent can drive from a shell (playwright-cli); skills that need a browser use it rather than one agent''s own browser tool' }

        # --- github-release ---------------------------------------------------------------

        @{ Id = 'hugoforte/openwhispr'
           Source = 'github-release'
           Optional = 'openwhispr'
           Unattended = $false
           Asset = 'OpenWhispr-Setup-*.exe'
           InstallArgs = @('/S', '/currentuser')
           Present = 'OpenWhispr *-hf.*'
           Note = 'Voice dictation whose voice assistant runs through the logged-in Claude Code, on the Claude subscription. Matched by its -hf. version, so an upstream OpenWhispr already installed is replaced rather than taken for it. The fork updates itself from its own releases. Not unattended: a 250 MB download and a desktop app arriving should be watched' }

        # rig is deliberately absent: it is an `npm link` of a local checkout, not an install.
        # Installing it from the registry would silently replace the checkout you develop in.

        # --- manual: yours to do, reported every run, never installed ------------------------

        @{ Id = 'developer-mode'
           Source = 'manual'
           Note = 'Turn on Developer Mode so symlinks work without elevation - every installer here depends on it'
           Url = 'ms-settings:developers' }

        @{ Id = 'gh-auth'
           Source = 'manual'
           Note = 'Authenticate the GitHub CLI: gh auth login. Needed to clone private repos and by the git credential helper' }

        @{ Id = 'sops-recipient'
           Source = 'manual'
           Note = 'Register this machine as an age recipient before secrets will decrypt - see ai/secrets/README.md, "Add a machine"' }

        @{ Id = 'openwhispr-first-run'
           Source = 'manual'
           Optional = 'openwhispr'
           Note = 'Open OpenWhispr and set it up: pick the dictation hotkey and a local Whisper model; under cleanup choose a local model; under Voice Assistant choose Local CLI Agent > Claude Code. Needs `claude` logged in to the subscription' }
    )
}
