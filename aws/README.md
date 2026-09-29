# AWS Configuration

The AWS CLI config (`~/.aws/config`) is not kept in this repo: it names accounts and roles, so it lives in an overlay (see [the README](../README.md#private-configuration-overlays)). `powershell/setup.ps1` and `sync.ps1` link `~/.aws/config` to the `aws/config` of this repo or of one overlay; two sources is an error, and none leaves the file alone.

## Files

- `credentials` - never committed (see `.gitignore`); SSO means it is not needed.

## SSO Authentication

The configuration uses AWS SSO (Single Sign-On) for authentication. No static credentials are stored anywhere.

## Setup on New Machine

When you run the setup script, or on the next sync, it will:
1. Find the one `aws/config` among this repo and the machine's overlays
2. Create the `~/.aws/` directory
3. Create a symbolic link from `~/.aws/config` to that file

Edits to the profiles then flow through the overlay's repo, and `sync.ps1` keeps the link pointing at whichever source the machine's overlays provide.

**After setup:** Run `aws sso login` to authenticate with your SSO provider.

## Managing Profiles

Use the PowerShell functions to manage profiles:
- `list-functions` - Show all available AWS commands
- `aws-switch-profile` - Interactive menu to switch profiles
- `aws-profile [name]` - Switch to a specific profile
- `aws-whoami` - See current AWS identity
