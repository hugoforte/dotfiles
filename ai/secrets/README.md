# Skill secrets

Credentials that project-level skills need (for example `app-db-query` in the the employer app repo) are stored here encrypted, decrypted once per machine, and symlinked into every checkout that has the skill. Plaintext never enters git: not this repo, not the app repos.

## How it works

```
ai/secrets/<skill>/<file>              encrypted with SOPS + age, committed
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
- **Per machine**: `machine.local.psd1` (git-ignored, copy the example) lists the directories whose children are checkouts, e.g. `C:\source`.
- **Deploy**: `powershell/deploy-secrets.ps1` decrypts, discovers checkouts one level under each search root, verifies each one's origin contains the registry's `Remote`, and links the files in. `sync.ps1` runs it after `install.sh` on machines that have a `machine.local.psd1`.

Safety properties of the deploy script:

- Idempotent. Re-running changes nothing when everything is in place.
- A real file found where a link should go is moved to `%USERPROFILE%\.agent-secrets\backups\<checkout>\<skill>\`, never left inside the checkout and never deleted.
- A failed decrypt leaves the previous decrypted copy untouched.
- `-Check` reports what would change and exits 1 on drift.
- `ai/install.sh --check` runs `check-encrypted.sh`, which fails if any file under `ai/secrets/<skill>/` lacks SOPS metadata.

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

Edit an existing file in place without a plaintext copy on disk:

```sh
sops edit ai/secrets/<skill>/.secrets.env
```

New skill: add an entry to `registry.psd1`, encrypt its files as above, run `deploy-secrets.ps1`, commit.

## Add a machine

On the new machine:

```sh
ssh-keygen -t ed25519 -N "" -C "hugo@$(hostname) dotfiles" -f ~/.ssh/id_ed25519
gh auth refresh -h github.com -s admin:public_key      # once per gh login
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname) dotfiles"
```

Then, from any machine that can already decrypt, add the new public key to `.sops.yaml` (all your keys are listed at `https://github.com/hugoforte.keys`) and re-encrypt:

```sh
sops updatekeys -y ai/secrets/*/.secrets.env ai/secrets/*/keys.local.json
git commit -am "Add <hostname> as secrets recipient" && git push
```

Back on the new machine: `git pull`, copy `machine.local.psd1.example` to `machine.local.psd1`, run `deploy-secrets.ps1`.

**No other machine available?** Use the recovery key: paste it into `%APPDATA%\sops\age\keys.txt` on the new machine, do the `updatekeys` step there, push, then delete `keys.txt`.

## Remove a machine

Delete its line from `.sops.yaml`, run the same `sops updatekeys` command, commit, push. That machine can decrypt nothing committed after that point.

## Rotate a credential

`sops edit` the file, commit, push. Every machine picks it up on its next sync and every checkout reads the new value through its link.
