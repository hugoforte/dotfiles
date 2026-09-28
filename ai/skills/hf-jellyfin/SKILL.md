---
name: hf-jellyfin
description: Administer Hugo's Jellyfin media server on hugo-media through its REST API. Use when asked to add, disable or remove a Jellyfin user, change a user's password or library access, scan libraries, or check what the server is doing.
---

# Jellyfin

Jellyfin runs on the home media server, reachable only over Tailscale, at the `JELLYFIN_URL` in its secrets file (below).

## Credentials

`~/.agent-secrets/hf-jellyfin/.secrets.env` holds `JELLYFIN_URL` and `JELLYFIN_API_KEY`, an admin API key made under Dashboard → API Keys. It is decrypted there by `deploy-secrets.ps1` from `ai/secrets/hf-jellyfin/` in the personal overlay (see the dotfiles README, "Private configuration: overlays"); if it is missing or still says `CHANGE_ME`, use the `hf-dotfiles-secrets` skill rather than asking for a key in chat. Never print the key.

```bash
set -a; . ~/.agent-secrets/hf-jellyfin/.secrets.env; set +a
jf() {  # jf <METHOD> <path> [json body]
    curl -s -X "$1" "$JELLYFIN_URL$2" -H "Authorization: MediaBrowser Token=\"$JELLYFIN_API_KEY\"" \
        ${3:+-H 'content-type: application/json' -d "$3"}
}
```

Shell state does not persist between tool calls, so repeat this block at the top of each command that needs it.

## Finding the shape of anything

The server publishes its own OpenAPI document at `$JELLYFIN_URL/api-docs/openapi.json` (no auth, about 2 MB). Query it with `jq` rather than guessing an endpoint or body; endpoints move between Jellyfin versions, and `/System/Info/Public` says which version this is.

```bash
curl -s "$JELLYFIN_URL/api-docs/openapi.json" | jq '.paths["/Users/New"].post.requestBody'
```

## Common jobs

| Job | Call |
|---|---|
| List users | `jf GET /Users \| jq '.[] \| {Name, Id, disabled: .Policy.IsDisabled, admin: .Policy.IsAdministrator}'` |
| Add a user | `jf POST /Users/New '{"Name":"…","Password":"…"}'` |
| Set a user's password | `jf POST "/Users/Password?userId=<id>" '{"NewPw":"…"}'` |
| Disable, enable, grant or limit access | read `jf GET /Users/<id>`, edit its `.Policy`, send the whole object back with `jf POST /Users/<id>/Policy "<policy json>"` |
| Libraries, with the ids `EnabledFolders` takes | `jf GET /Library/VirtualFolders \| jq '.[] \| {Name, ItemId}'` |
| Scan every library | `jf POST /Library/Refresh` |
| Who is watching now | `jf GET /Sessions` |
| Delete a user | `jf DELETE /Users/<id>` |

A policy post replaces the whole policy, so always start from the current one. To limit a user to some libraries, set `EnableAllFolders` to `false` and `EnabledFolders` to those libraries' `ItemId`s.

## New users

- Ask for the name, which libraries, and whether they may download or transcode, unless the user already said.
- New users get the server's default policy, which grants every library. Set the policy straight after creating the user if access should be narrower.
- Generate a password if none was given, and tell the user it once, in the reply. It is not stored anywhere else.

## Rules

- Read freely. Change a user or setting only when the user asked for that change.
- Confirm before deleting a user or making one an administrator.
