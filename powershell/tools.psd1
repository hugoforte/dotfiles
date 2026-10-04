# The tools and programs a machine of mine needs. Read by install-tools.ps1.
#
# Every entry is a hashtable:
#
#   Id          winget package id, npm package name, or a slug for a manual step
#   Source      'winget' | 'npm' | 'manual'
#   Unattended  $false to keep sync.ps1 from installing it behind your back (default $true)
#   Note        what it is, or - for manual entries - what you have to do
#   Url         optional, for manual entries that need a page
#
# Entries install only when missing; nothing here is ever upgraded or uninstalled by the
# installer. Add a tool, push, and every machine picks it up on its next sync.
#
# There is deliberately no per-machine filtering: both machines are set up the same way.
# See the design note in the rig data root if that stops being true.

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
    )
}
