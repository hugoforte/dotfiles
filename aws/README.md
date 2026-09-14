# AWS Configuration

AWS CLI config, symlinked to `~/.aws/config` by `powershell/setup.ps1`.

## Files

- `config` - AWS CLI configuration (profiles, SSO settings, regions). The only file managed here.
- `credentials` - never committed (see `.gitignore`); SSO means it is not needed.

## SSO Authentication

This configuration uses AWS SSO (Single Sign-On) for authentication. No static credentials are stored.

The `config` file contains your SSO profile configurations and is safe to commit to a private repository.

## Setup on New Machine

When you run the setup script, it will automatically:
1. Detect if `aws/config` exists in this repo
2. Create the `~/.aws/` directory
3. Create a symbolic link from `~/.aws/config` to this file

This means any changes you make to AWS profiles will automatically sync via git!

**After setup:** Run `aws sso login` to authenticate with your SSO provider.

## Managing Profiles

Use the PowerShell functions to manage profiles:
- `list-functions` - Show all available AWS commands
- `aws-switch-profile` - Interactive menu to switch profiles
- `aws-profile [name]` - Switch to a specific profile
- `aws-whoami` - See current AWS identity
