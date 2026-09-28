---
name: hf-scryer
description: Inspect and administer Hugo's Scryer media manager (the Sonarr/Radarr replacement on hugo-media) through its GraphQL API. Use when asked about Scryer settings, indexers, download clients, seeding profiles or minimum seeders, or downloads stuck in the queue (stalled, 0 seeds, "Downloading metadata").
---

# Scryer

Scryer runs on the home media server, reachable only over Tailscale, at the `SCRYER_URL` in its secrets file (below). Everything the web UI does goes through one GraphQL endpoint, `/graphql`, so work against that rather than driving the UI.

## Credentials

`~/.agent-secrets/hf-scryer/.secrets.env` holds `SCRYER_URL`, `SCRYER_USERNAME` and `SCRYER_PASSWORD`, plus `SCRYER_BACKUP_KEY`, the key Scryer's automatic backups are encrypted with and the one a restore asks for. It is decrypted there by `deploy-secrets.ps1` from `ai/secrets/hf-scryer/` in the personal overlay (see the dotfiles README, "Private configuration: overlays"); if it is missing or still says `CHANGE_ME`, use the `hf-dotfiles-secrets` skill rather than asking for the password in chat. Never print the password or the token.

## Signing in

`login` returns a bearer token. Every other call sends it as `Authorization: Bearer <token>`.

```bash
set -a; . ~/.agent-secrets/hf-scryer/.secrets.env; set +a
gql() {  # gql '<query>' ['<variables json>']
    curl -s "$SCRYER_URL/graphql" -H 'content-type: application/json' \
        ${SCRYER_TOKEN:+-H "authorization: Bearer $SCRYER_TOKEN"} \
        -d "$(jq -n --arg q "$1" --argjson v "${2:-{\}}" '{query: $q, variables: $v}')"
}
SCRYER_TOKEN=$(gql 'mutation($i: LoginInput!) { login(input: $i) { token } }' \
    "$(jq -n --arg u "$SCRYER_USERNAME" --arg p "$SCRYER_PASSWORD" '{i: {username: $u, password: $p}}')" \
    | jq -r '.data.login.token')
```

Shell state does not persist between tool calls, so repeat this block at the top of each command that needs it.

## Finding the shape of anything

Introspection is on. Look up a type rather than guessing its fields:

```bash
gql '{ __type(name: "UpdateSeedingProfileInput") { inputFields { name type { name ofType { name } } } } }'
```

`{ __schema { mutationType { fields { name } } } }` lists every mutation.

## Common jobs

| Job | Operation |
|---|---|
| Who am I, what can I do | `{ me { username appPermissions } }` |
| Seeding profiles and their minimum seeders | `{ seedingProfiles { id name minimumSeeders ratio seedTimeMinutes } }` |
| The default minimum seeders (applies when no profile covers an indexer) | `{ defaultSeedingProfile { seedingProfileId minimumSeedersFloor } }` |
| Indexers, their profile and Prowlarr minimum | `{ indexers { id name isEnabled seedingProfileId hasProwlarrSeedCriteria prowlarrMinimumSeeders lastHealthStatus lastErrorMessage } }` |
| Download clients | `{ downloadClientConfigs { id name clientType isEnabled status lastError } }` |
| The queue | `{ downloadQueue { titleName clientId clientType downloadClientItemId state displayState progressPercent attentionRequired attentionReason } }` |
| Set the default minimum seeders | `setMinimumSeedersFloor(input: { minimumSeedersFloor: N })` |
| Change a profile | `updateSeedingProfile(input: {...})` — send every field; read the profile first |
| Give an indexer a profile | `setIndexerSeedingProfile(input: {...})` |
| Fail a stuck download and search again | `markTrackedDownloadFailed(input: { clientId, clientType, downloadClientItemId })` |
| Remove a download | `deleteDownload(input: { clientId, clientType, downloadClientItemId })` |
| A title by id | `title(id: "…") { name facet monitored collections { id collectionIndex monitored episodesOwned episodesTotal } }` — `titles(query:)` returns a catalogue page, not a list |
| Monitor a season | `setCollectionMonitored(input: { collectionId, monitored: true })`, the season's id from `collections` |
| Monitor a movie or series | `setTitleMonitored(input: { titleId, monitored: true })` |
| Search now | `triggerAcquisitionSearch(input: { titleId, seasonNumber, wantedKind: MISSING })`, then poll `acquisitionSearchJob(id:)` for `grabbedCount`. One job runs at a time; a second is refused until the first finishes |
| Change a quality profile | read `qualityProfileSettings`, send every profile back through `saveQualityProfileSettings` with `replaceExisting: false` |

qBittorrent tags every torrent Scryer sends it with `scryer-title-<id>`, which is the quickest way from a stuck torrent to its title.

## Downloads stuck at "Downloading metadata"

Check the download client before blaming the release. qBittorrent's Web API answers on `http://127.0.0.1:8081/api/v2` without a password from this machine:

- `GET /transfer/info`: `connection_status` of `disconnected` with `dht_nodes` of 0 means qBittorrent itself is offline, and every torrent will look dead.
- `GET /log/main?last_known_id=-1`: "Failed to listen on IP … forbidden by its access permissions" means the listen port is inside a range Windows has reserved for Hyper-V. `netsh interface ipv4 show excludedportrange protocol=tcp` lists them, and the ranges move at each reboot, so the listen port belongs below 49152.
- It is bound to the ProtonVPN adapter (`current_network_interface`) as a kill switch. If ProtonVPN is disconnected, qBittorrent stays offline, which is intended.

Only when qBittorrent is connected and a torrent still has no peers is the release dead. Then `markTrackedDownloadFailed` is usually the answer: it fails the release so Scryer grabs a different one, where deleting it in qBittorrent alone lets Scryer grab the same dead release again. `skipReacquire: true` fails it without searching again. Failing a release does not remove the torrent from qBittorrent; delete it there with `POST /torrents/delete` (`hashes`, `deleteFiles=true`).

## Backups and restore

Scryer makes an encrypted backup daily at 03:00 into `%LOCALAPPDATA%\ScryerMedia\Scryer\backups`, encrypted with `SCRYER_BACKUP_KEY`. `{ backups { filename createdAt trigger status } }` lists them, and `createBackup(input: { password })` makes one now. The `hugoforte/media-backups` repo bundles the newest one nightly, and restores it.

- **Its scheduler plans only when Scryer starts.** After turning auto-backups on, the next run is set at the next start; `autoBackupSettings { nextRunAt }` (UTC) says when.
- **A restore only works on a Scryer that hasn't been set up.** On one that has, `inspectRestoreBundle` refuses with "restore is only available while setup is still incomplete". Restore into a fresh data folder.
- **A fresh Scryer shows an "upgrading" page for a while** (every URL answers with it) while it migrates. Wait for it to go before calling the API.
- **Unauthenticated calls on a fresh Scryer need the web client's proof.** `GET /authless-client` returns `{proof}`; send it as `x-scryer-web-client`, with that request's cookies.
- **Uploads are GraphQL multipart** (`operations`, `map`, `0=@file`) with `GraphQL-Preflight: 1`.
- **After `applyRestoreBundle`, Scryer respawns itself**, with the encryption key from the bundle, so stored credentials come back. The process you started is not the one left running.

## Rules

- Read freely. Change a setting only when the user asked for that change.
- Before any change, show the current value and the new one.
- Confirm before anything that removes data: `deleteDownload`, deleting a profile, indexer or client.
- If the API cannot do something, the web UI is the fallback. It needs the same sign-in, and the user can sign in there themselves.
