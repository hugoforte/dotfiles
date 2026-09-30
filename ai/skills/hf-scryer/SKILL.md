---
name: hf-scryer
description: Inspect and administer Hugo's Scryer media manager (the Sonarr/Radarr replacement on hugo-media) through its GraphQL API. Use when asked about Scryer settings, indexers, download clients, seeding profiles or minimum seeders, grabbing a particular release or season pack, downloads stuck in the queue (stalled, 0 seeds, "Downloading metadata") or left behind in qBittorrent, fake downloads, or upgrading Scryer.
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

Shell state does not persist between tool calls, so repeat this block at the top of each command that needs it. Unauthenticated queries answer nothing useful, so signing in is also how to tell whether Scryer is up: a failed connection means it is down. Quick repeated sign-ins are throttled, and then `login` answers with a `RATE_LIMITED` error and `retryAfterSeconds`, the token comes out as `null`, and every later query is refused; wait that long and sign in again.

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
| Change a quality profile | read `qualityProfileSettings`, send every profile back through `saveQualityProfileSettings` with `replaceExisting: false`, along with `globalProfileId`, `globalScoringPersona`, `categorySelections` and `categoryPersonaSelections` |
| Disable an indexer | Disable it in Prowlarr (see `hf-prowlarr`). `updateIndexerConfig(input: { id, isEnabled: false })` here is a local override that survives Prowlarr syncs, so re-enabling one takes `isEnabled: true` here as well as Prowlarr's `enable` |
| Search a title's releases | `searchReleases(input: { titleId, limit })` returns each result's `seeders`, `autoDecisionCode`, `qualityProfileDecision { releaseScore }`, `candidateToken` and `queueScope`. Without `season` it returns season packs across the series; `season` needs `episode` as well |
| Grab a chosen release | `queueExistingTitleDownload(input: { titleId, candidateToken, sizeBytes, scope: { collection: <season id> } })`, with the token and `sizeBytes` exactly as a fresh search returned them. The token fixes the scope, so the `scope` passed is only required, never used. `CONFLICT` means a download already holds that scope; `replaceInProgress: true` replaces it, removing those torrents and leaving their files on disk |
| Why a release was or wasn't grabbed | `titleAcquisitionDiagnostics(titleId:) { recentDecisions { releaseTitle decisionCode candidateScore explanationJson } }`; `explanationJson` names the indexer (`candidate.source`) and carries the scoring log |
| A title's history | `titleHistory(filter: { titleIds: [...], eventTypes: [GRABBED, IMPORT_SKIPPED], limit }) { items { eventType sourceTitle sourceProvider downloadId sourceRef skipReason dataJson } }`. Event types go in as uppercase enums and come back lowercase (`grabbed`). The torrent's hash is `downloadId` on grabs and `sourceRef` on imports |
| Download history | `downloadHistory(limit: 50, offset:) { hasMore items {...} }`, 50 rows a page at most, and it stops at 500 |

Season packs of compact x265 encodes (about 8 GB a season) score as "very small for 1080p" and lose to single episodes unless the profile's `criteria { scoringOverrides { preferCompactEncodes } }` is on; the Series (1080p) profile has it on.

qBittorrent tags every torrent Scryer sends it with `scryer-title-<id>`, which is the quickest way from a stuck torrent to its title.

## Stuck, stalled or fake downloads

The **Stalled Downloads** scheduled task fails stalled and fake Scryer torrents on its own at 06:00 and 18:00 (`watchdog/Remove-StalledDownloads.ps1` in the `hugoforte/media-backups` repo, whose README gives the rules). Read its newest log, `%LOCALAPPDATA%\media-backups\logs\stalled-*.log`, before acting by hand; `-WhatIf` shows what it would do now.

Check the download client before blaming the release. qBittorrent's Web API answers on `http://127.0.0.1:8081/api/v2` without a password from this machine:

- `GET /transfer/info`: `connection_status` of `disconnected` with `dht_nodes` of 0 means qBittorrent itself is offline, and every torrent will look dead.
- `GET /log/main?last_known_id=-1`: "Failed to listen on IP … forbidden by its access permissions" means the listen port is inside a range Windows has reserved for Hyper-V. `netsh interface ipv4 show excludedportrange protocol=tcp` lists them, and the ranges move at each reboot, so the listen port belongs below 49152.
- It is bound to the ProtonVPN adapter (`current_network_interface`) as a kill switch. If ProtonVPN is disconnected, qBittorrent stays offline, which is intended.

Only when qBittorrent is connected and a torrent still has no peers is the release dead. Then `markTrackedDownloadFailed` is usually the answer: it fails the release so Scryer grabs a different one, where deleting it in qBittorrent alone lets Scryer grab the same dead release again. `skipReacquire: true` fails it without searching again. Failing a release does not remove the torrent from qBittorrent; delete it there with `POST /torrents/delete` (`hashes`, `deleteFiles=true`).

## Torrents left behind in qBittorrent

Scryer removes a torrent from qBittorrent only after importing it and seeding it to its profile's goal. A torrent whose import was skipped stays for good, stopped once qBittorrent's seeding limit runs out. The `IMPORT_SKIPPED` events in `titleHistory` name each one, by `sourceRef` (the hash) and `skipReason`, and `dataJson`'s `reason` says why in words:

- **`no_video_files`** is usually a **fake**: an executable named like the episode. qBittorrent's excluded file names keep the executable from downloading, and the task above removes the torrent at its next run, so a fake younger than that run is expected. `GET /torrents/files?hash=` shows what it holds. Safe to delete.
- **`already_imported`**: the library already holds an identical file. Safe to delete.
- **`policy_mismatch`**: the file contradicts what the release advertised (a "2160p" that is 1440p), so it was never imported and may be the only copy. So is anything with no `skipReason`. The user decides.

Imports hardlink into the library where they can, so deleting a torrent's files leaves the library copy intact but frees little space. Confirm before deleting.

## Upgrading Scryer

Install the new release over the old one; never uninstall. Since 0.21.2, uninstalling deletes `%LOCALAPPDATA%\ScryerMedia\Scryer` (all but a non-empty `backups` folder) and the Credential Manager entry holding the key its stored passwords are encrypted with, so going back a version means reinstalling the old one and restoring a backup. In order:

1. **Take a restore point.** Run `createBackup(input: { password: <SCRYER_BACKUP_KEY> })`, the backup key, which the restore asks for, never the login password. Then run the `media-backups` backup task, whose bundle takes the newest Scryer backup file; otherwise it holds the 03:00 one, from before any change made since.
2. **Install** the release's `scryer-windows-x86_64-winget.msi`, checked against its `scryer-checksums.txt`.
3. **Start Scryer detached from your shell**, or it stops when your command does: `Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = '"C:\Program Files\Scryer Media\Scryer\scryer-tray.exe" --login-start' }`.
4. **Wait for the migration.** The first start migrates the database, which can take minutes and grows it; sign in to tell when it is done.
5. **Update Scryer's pin**, its `Version` and `Url` together, in `media-backups`' `setup/packages.psd1`, since a restore installs the pinned version.

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
- Confirm before anything that removes data: `deleteDownload`, `replaceInProgress`, deleting a torrent in qBittorrent, or deleting a profile, indexer or client.
- If the API cannot do something, the web UI is the fallback. It needs the same sign-in, and the user can sign in there themselves.
