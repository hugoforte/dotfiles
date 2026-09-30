---
name: hf-prowlarr
description: Inspect and administer Hugo's Prowlarr indexer manager on hugo-media through its REST API. Use when asked about indexers, why searches return nothing, indexer health or failures, sync profiles and their minimum seeders, or which apps Prowlarr pushes indexers to.
---

# Prowlarr

Prowlarr runs on the home media server, reachable only over Tailscale, at the `PROWLARR_URL` in its secrets file (below). It owns the indexers, and Scryer pulls them from it as Prowlarr-managed copies. An indexer fix usually belongs here, not in Scryer. Disabling one here (`enable: false`, with a `PUT`) reaches Scryer at its next sync. Scryer also keeps a local disable of its own that survives syncs, so re-enabling an indexer Scryer disabled takes Scryer too (see `hf-scryer`).

## Credentials

`~/.agent-secrets/hf-prowlarr/.secrets.env` holds `PROWLARR_URL` and `PROWLARR_API_KEY`, the key from Settings → General. It is decrypted there by `deploy-secrets.ps1` from `ai/secrets/hf-prowlarr/` in the personal overlay (see the dotfiles README, "Private configuration: overlays"); if it is missing or still says `CHANGE_ME`, use the `hf-dotfiles-secrets` skill rather than asking for the key in chat. Never print the key.

```bash
set -a; . ~/.agent-secrets/hf-prowlarr/.secrets.env; set +a
pr() {  # pr <METHOD> <path> [json body]
    curl -s -X "$1" "$PROWLARR_URL/api/v1$2" -H "X-Api-Key: $PROWLARR_API_KEY" \
        ${3:+-H 'content-type: application/json' -d "$3"}
}
```

Shell state does not persist between tool calls, so repeat this block at the top of each command that needs it.

## Finding the shape of anything

The server serves its OpenAPI document at `$PROWLARR_URL/api/v1/openapi.json`, behind the same key. Query it with `jq` rather than guessing an endpoint or body.

## Common jobs

| Job | Call |
|---|---|
| Version and health warnings | `pr GET /system/status`, `pr GET /health` |
| Indexers | `pr GET /indexer \| jq '.[] \| {id, name, enable, protocol, appProfileId}'` |
| Indexers that are failing, and until when | `pr GET /indexerstatus` |
| Query and grab counts, failures per indexer | `pr GET /indexerstats` |
| Sync profiles, with their minimum seeders | `pr GET /appprofile` |
| Apps it syncs indexers to | `pr GET /applications \| jq '.[] \| {id, name, syncLevel}'` |
| Search across indexers | `pr GET "/search?query=<terms>&type=search" \| jq '.[] \| {title, indexer, seeders, size}'` |
| Test one indexer | `pr POST /indexer/test "<the indexer's json from GET /indexer/<id>>"` |
| Push indexers to the apps now | `pr POST /command '{"name":"ApplicationIndexerSync"}'` |
| Change an indexer or profile | read it with `GET …/<id>`, edit the JSON, send the whole object back with `PUT …/<id>` |

A sync profile's `minimumSeeders` travels to Scryer with each indexer it covers. Scryer shows it as the indexer's Prowlarr minimum and uses it unless a Scryer seeding profile is assigned to that indexer.

## Rules

- Read freely. Change an indexer, profile or app only when the user asked for that change.
- Before any change, show the current value and the new one.
- Confirm before deleting an indexer, profile or app.
