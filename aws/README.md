# AWS Configuration

The AWS CLI config (`~/.aws/config`) is not kept in this repo: it names accounts and roles, so it lives in overlays (see [the README](../README.md#private-configuration-overlays)). Each employer's overlay ships its own `aws/config`, and `powershell/setup.ps1`, `sync.ps1` and `macos/setup.sh` merge every one of them into `~/.aws/config` ([ADR 0010](../docs/adr/0010-aws-config-is-generated.md)).

## Files

- `credentials` - never committed (see `.gitignore`); SSO means it is not needed.

## SSO Authentication

The configuration uses AWS SSO (Single Sign-On) for authentication. No static credentials are stored anywhere.

## Setup on New Machine

When you run the setup script, or on the next sync, it will:
1. Find every `aws/config` among this repo and the machine's overlays
2. Create the `~/.aws/` directory
3. Write `~/.aws/config`: a header naming how many files it merged, then each one under a `# from <path>` line, the repo first and then the overlays in the order `machine.local.psd1` lists them

The same section, such as `[default]` or `[profile dev]`, in two of them is an error naming both, and `~/.aws/config` is left as it was. A link at `~/.aws/config`, which setup made before the file was generated, is replaced without a backup; a file dotfiles did not write is backed up first. With no `aws/config` left, the generated file is removed.

**Add a profile in its overlay**, not in `~/.aws/config`: the next sync replaces the generated file, and an edited one, such as by `aws configure sso`, is backed up and replaced.

**After setup:** Run `aws sso login` to authenticate with your SSO provider.

## Managing Profiles

Use the PowerShell functions to manage profiles:
- `list-functions` - Show all available AWS commands
- `aws-switch-profile` - Interactive menu to switch profiles
- `aws-profile [name]` - Switch to a specific profile
- `aws-whoami` - See current AWS identity
