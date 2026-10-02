# Skill secrets

Credentials that project-level skills need (for example a database-query skill in an app repo) are stored here or in an overlay, encrypted, decrypted once per machine, and symlinked into every checkout that has the skill. Plaintext never enters git: not this repo, not the app repos.

## How it works

```
<root>/ai/secrets/<skill>/<file>       encrypted with SOPS + age, committed
                                       <root> is this repo or an overlay
        │  deploy-secrets.ps1 (sops decrypt)
        ▼
%USERPROFILE%\.agent-secrets\<skill>\<file>   plaintext, one copy per machine
        │  symlink
        ▼
C:\source\<checkout>\.claude\skills\<skill>\<file>   every matching checkout
```

- **Encryption**: SOPS with age recipients. Key names stay readable, values are encrypted, so diffs make sense.
- **Identity per machine**: its SSH key at `~/.ssh/id_ed25519`. SOPS finds it automatically. The private key never leaves the machine.
- **Recovery key**: a plain age key held only in the password manager. Its public half is a permanent recipient. It bootstraps a new machine and survives the loss of every laptop.
- **Registry**: `registry.psd1` lists each managed skill, the marker path that identifies a checkout using it, the expected origin URL, and the files.
- **Per machine**: `machine.local.psd1` (git-ignored, copy the example) lists the directories whose children are checkouts, e.g. `C:\source`, and the machine's overlays.
- **Overlays**: private directories laid out like this repo's root, usually in a private repo. Each may carry its own `ai/secrets/registry.psd1`, `ai/secrets/<skill>/` and `.sops.yaml`. The registries of this repo and every overlay merge; a skill decrypts from the directory that registered it, and the same skill id in two registries is an error. No tracked file here names an overlay. The same overlays also supply `aws/config` (from exactly one place) and git config fragments to `powershell/setup.ps1`, and skills and Bruno collections to `ai/install.sh`.
- **Deploy**: `powershell/deploy-secrets.ps1` merges the registries, decrypts, discovers checkouts one level under each search root, verifies each one's origin contains the registry's `Remote`, and links the files in. `sync.ps1` runs it after `install.sh` on machines that have a `machine.local.psd1`.

Safety properties of the deploy script:

- Idempotent. Re-running changes nothing when everything is in place.
- A real file found where a link should go is moved to `%USERPROFILE%\.agent-secrets\backups\<checkout>\<skill>\`, never left inside the checkout and never deleted.
- A failed decrypt leaves the previous decrypted copy untouched.
- `-Check` reports what would change and exits 1 on drift.
- An overlay listed in `machine.local.psd1` that does not exist is an error, not a skip.
- `ai/install.sh --check` runs `check-encrypted.sh` for this repo and for each overlay's `ai/secrets/`; it fails if any file under `<skill>/` lacks SOPS metadata. `check-encrypted.sh <dir>` audits one directory.

## Secrets in an overlay

Everything below works the same inside an overlay, with two differences: run the commands from the overlay directory so SOPS picks up the overlay's own `.sops.yaml` (its recipients may differ from this repo's), and audit with `sh <dotfiles>/ai/secrets/check-encrypted.sh ai/secrets`. Commit and push in the overlay's repo, not this one.

## Commands

```powershell
.\powershell\deploy-secrets.ps1           # decrypt, discover, link
.\powershell\deploy-secrets.ps1 -Check    # report only
```

## Add or update a secret file

Run from the repo root in Git Bash. SOPS matches the creation rule on the output path, hence `--filename-override`. The `tr` strips carriage returns, which the dotenv parser rejects.

```sh
tr -d '\r' < /path/to/plain/.secrets.env > /tmp/plain.env
sops encrypt --filename-override ai/secrets/<skill>/.secrets.env /tmp/plain.env > ai/secrets/<skill>/.secrets.env
rm /tmp/plain.env
sops decrypt ai/secrets/<skill>/.secrets.env | head -3     # sanity check, values visible
```

Edit an existing file in place without a plaintext copy on disk. In PowerShell, the profile sets `SOPS_EDITOR` to `code --wait`, so the file opens in VS Code and is re-encrypted when you close its tab:

```sh
sops edit ai/secrets/<skill>/.secrets.env
```

New skill: add an entry to `registry.psd1`, encrypt its files as above, run `deploy-secrets.ps1`, commit.

A shipped skill (one under `ai/skills/`) has no checkout to link into. Give its entry only `Id` and `Files`; `deploy-secrets.ps1` decrypts the files to `%USERPROFILE%\.agent-secrets\<Id>\` and links nothing, and the skill reads them from there. Linking into `ai/skills/<name>/` instead would put plaintext inside this repo's checkout.

## Add a machine

On the new machine:

```sh
ssh-keygen -t ed25519 -N "" -C "hugo@$(hostname) dotfiles" -f ~/.ssh/id_ed25519
gh auth refresh -h github.com -s admin:public_key      # once per gh login
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname) dotfiles"
```

Then, from any machine that can already decrypt, add the new public key to the `.sops.yaml` of every overlay the machine should read (all your keys are listed at `https://github.com/hugoforte.keys`), and of this repo if it holds secrets. Re-encrypt from inside each one:

```sh
cd <overlay>
sops updatekeys -y ai/secrets/*/.secrets.env ai/secrets/*/keys.local.json
git commit -am "Add <hostname> as secrets recipient" && git push
```

Back on the new machine: `.\powershell\install-overlays.ps1 -Repo <owner>/<private-repo>`, which clones the overlays, lists them in `machine.local.psd1` and deploys.

**No other machine available?** Use the recovery key: paste it into `%APPDATA%\sops\age\keys.txt` on the new machine, do the `updatekeys` step there, push, then delete `keys.txt`.

## Remove a machine

Delete its line from each `.sops.yaml` it is in, run the same `sops updatekeys` command in each, commit, push. That machine can decrypt nothing committed after that point.

## Rotate a credential

`sops edit` the file, commit, push. Every machine picks it up on its next sync and every checkout reads the new value through its link.
