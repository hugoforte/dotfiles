---
name: hf-dotfiles-secrets
description: Manage the encrypted skill secrets in the dotfiles repo. Use when a skill needs credentials on a new machine, a secret file must be added, updated or rotated, a machine must be added or removed as a recipient, or deploy-secrets.ps1 reports problems.
---

# Dotfiles secrets

The procedures live in `ai/secrets/README.md` of the dotfiles repo. Read it first, then follow the matching section. Do not improvise around SOPS.

## Ground rules

- Never print a decrypted value into the conversation. Show key names, lengths or hashes instead.
- Never write plaintext into any git checkout. Temporary plaintext goes under `/tmp` and is removed in the same step.
- Never copy a private key between machines. Each machine generates its own SSH key; only public keys travel.
- Every change ends with `sh ai/secrets/check-encrypted.sh` passing and a commit.
- A skill may be registered in an overlay rather than here: the machine's `machine.local.psd1` lists them. Work on an overlay's secret from inside that overlay, so its own `.sops.yaml` applies, and commit in the overlay's repo. The README's "Secrets in an overlay" has the details.

## Which section

| Situation | Section in the README |
|---|---|
| A checkout's skill lacks its secret files | run `deploy-secrets.ps1`; if the skill is unknown, "Add or update a secret file" |
| New laptop | "Add a machine" |
| Laptop lost or retired | "Remove a machine" |
| A credential changed | "Rotate a credential" |
| Decrypt fails on this machine | this machine is not a recipient: "Add a machine" |
| A stray real file was found where a link belongs | it was moved to `%USERPROFILE%\.agent-secrets\backups\`; compare before discarding |

## Verifying

```powershell
.\powershell\deploy-secrets.ps1 -Check
```

```sh
./ai/install.sh --check
```

Both must exit 0 when you are done.
