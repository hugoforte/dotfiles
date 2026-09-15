# Secrets

SOPS-encrypted files for skills that need credentials. Values are encrypted; key names stay readable so diffs make sense. Nothing in this folder is usable without one of the recipients in `.sops.yaml` at the repo root.

- Each machine's identity is its SSH key at `~/.ssh/id_ed25519`, generated on that machine and never copied.
- A recovery key exists only in the password manager. Paste it to `%APPDATA%\sops\age\keys.txt` on a machine that has no SSH key registered yet, decrypt, add the machine's SSH public key, `sops updatekeys`, push, then delete the pasted key.

Layout and deployment are described in the sections that follow as they are built.
