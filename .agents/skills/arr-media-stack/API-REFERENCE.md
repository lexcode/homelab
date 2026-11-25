# API reference

Companion to [`SKILL.md`](SKILL.md). Every path and field name below was exercised against the running stack on `rasp5-1` (2026-11) unless marked otherwise. Versions at that time: Radarr 6.4.4, Sonarr 4.0.20, Bazarr 1.6.2, Seerr 3.5.2, FlareSolverr 3.5.2, jq 1.6.

Set the target once — the paths are relative to the repo root on the Pi:

```bash
H=192.168.0.24          # localhost when running on the Pi
RKEY=$(grep -oP '(?<=<ApiKey>)[^<]+' media/data/radarr/config.xml)
SKEY=$(grep -oP '(?<=<ApiKey>)[^<]+' media/data/sonarr/config.xml)
LKEY=$(grep -oP '(?<=<ApiKey>)[^<]+' media/data/lidarr/config.xml)
PKEY=$(grep -oP '(?<=<ApiKey>)[^<]+' media/data/prowlarr/config.xml)
BKEY=$(python3 -c 'import yaml;print(yaml.safe_load(open("media/data/bazarr/config/config.yaml"))["auth"]["apikey"])')
EKEY=$(python3 -c 'import json;print(json.load(open("media/data/seerr/settings.json"))["main"]["apiKey"])')
# slskd: no key until one is created in its UI; it then lives in media/data/slskd/slskd.yml
# under web -> authentication -> api_keys
```

Response shapes are documented where they are counter-intuitive. When a call surprises you, read the failure: `404` with a JSON `message` is a wrong route or API version, `401` is a wrong key.

## Radarr / Sonarr / Lidarr (API v3, v3, **v1**)

Lidarr is still on v1 — `/api/v3/*` returns `404` there. Substitute `movie`/`series`/`artist`, and the port: 7878, 8989, 8686.

```bash
# liveness, no key
curl -s "http://$H:7878/ping"                     # {"status":"OK"}

curl -s -H "X-Api-Key: $RKEY" "http://$H:7878/api/v3/system/status" \
  | jq '{version, appName, startTime, databaseType, isDebug}'

# health warnings: failed notifications, missing indexers, bad root folders
curl -s -H "X-Api-Key: $RKEY" "http://$H:7878/api/v3/health" | jq '.[] | {type, source, message}'

# the Emby/Jellyfin link: notify must be off — Jellyfin has no /emby/Notifications, so the
# connection fails its test and raises "Notifications unavailable due to failures"
curl -s -H "X-Api-Key: $RKEY" "http://$H:7878/api/v3/notification" \
  | jq '.[] | {id, impl: .implementation, notify: ([.fields[]|select(.name=="notify")|.value][0]),
      updateLibrary: ([.fields[]|select(.name=="updateLibrary")|.value][0])}'

# free space per mounted path — watch for a share that silently became the SD card
curl -s -H "X-Api-Key: $RKEY" "http://$H:7878/api/v3/diskspace" \
  | jq '.[] | {path, label, freeSpace, totalSpace}'

# scheduled tasks, and the only reliable way to learn this instance's command names
curl -s -H "X-Api-Key: $RKEY" "http://$H:7878/api/v3/system/task" \
  | jq -r '.[] | select(.interval > 0) | .taskName'
```

### Queue and import failures

```bash
curl -s -H "X-Api-Key: $SKEY" "http://$H:8989/api/v3/queue?pageSize=50" | jq '{total: .totalRecords,
  records: [.records[] | {title, status, trackedDownloadState, trackedDownloadStatus, statusMessages, sizeleft}]}'
```

`trackedDownloadState: downloading` with `trackedDownloadStatus: ok` is healthy. `importPending` plus a `statusMessages` entry names the actual cause: a file that is not there, a permission error, or an unmounted path.

```bash
curl -s -H "X-Api-Key: $RKEY" \
  "http://$H:7878/api/v3/history?pageSize=30&sortKey=date&sortDirection=descending" \
  | jq '.records[] | select(.eventType == "downloadFailed") | {date, sourceTitle, data}'
```

`eventType` is a **string**, not an integer: `grabbed`, `downloadFolderImported`, `downloadFailed`, `movieFileRenamed`. History record keys: `id, eventType, sourceTitle, date, data, quality, qualityCutoffNotMet, languages, customFormatScore, customFormats, downloadId, movieId`.

### Downloads, roots, profiles

```bash
curl -s -H "X-Api-Key: $RKEY" "http://$H:7878/api/v3/downloadclient" \
  | jq '.[] | {name, enable, impl: .implementation,
      fields: [.fields[] | select(.name | test("host|port|category|urlBase|useSsl")) | {(.name): .value}]}'

curl -s -H "X-Api-Key: $RKEY" "http://$H:7878/api/v3/rootfolder" | jq '.[] | {path, accessible, freeSpace}'
curl -s -H "X-Api-Key: $RKEY" "http://$H:7878/api/v3/qualityprofile" | jq '.[] | {id, name}'

curl -s -H "X-Api-Key: $RKEY" "http://$H:7878/api/v3/movie" \
  | jq '.[] | select(.hasFile == false and .monitored) | {id, title, year}'
curl -s -H "X-Api-Key: $SKEY" "http://$H:8989/api/v3/series" \
  | jq '.[] | {id, title, episodeFileCount, episodeCount, monitored}'
```

Live reality worth knowing: Radarr's qBittorrent client points at `192.168.0.24:8080` while Sonarr's points at `172.39.0.2:8080`. Both work — the first goes out to the published port on the LAN, the second over `servarrnetwork`. A 502 through either path means a different thing, so read the `host` field before guessing.

`accessible: false` on a root folder is usually a dropped CIFS mount, not permissions.

### Why a search grabbed nothing

```bash
curl -s -H "X-Api-Key: $RKEY" "http://$H:7878/api/v3/release?movieId=<id>" \
  | jq '.[] | select(.rejected) | {title, indexer, seeders, rejections}'
```

The rejections spell out the decision, e.g. `"49.4 GB is larger than maximum allowed 27.0 GB"`, `"Original Language (English) is wanted, but found Hindi, Spanish (Latino)"`, `"Remux-2160p is not wanted in profile"`. Find a missing movie's id with the `movie` query above. This call queries every indexer, so allow it time.

### Commands

`POST /api/v3/command` with `{"name": "..."}`. Enumerate real names with `GET /api/v3/system/task` (`jq -r '.[].taskName'`) rather than trusting a list.

| App | Command | Arguments |
| --- | --- | --- |
| Radarr | `RefreshMovie` / `RescanMovie` | `movieIds` |
| Radarr | `MoviesSearch` | `movieIds` — scoped, prefer this |
| Radarr | `MissingMoviesSearch` | none — library-wide |
| Sonarr | `RefreshSeries` / `RescanSeries` | `seriesId` |
| Sonarr | `SeriesSearch` / `SeasonSearch` / `EpisodeSearch` | `seriesId`, `seasonNumber`, `episodeIds` |
| Sonarr | `MissingEpisodeSearch` | none — library-wide |
| All | `RssSync`, `CheckForUpdate` | none |

```bash
curl -s -X POST -H "X-Api-Key: $RKEY" -H "Content-Type: application/json" \
  -d '{"name": "RescanMovie", "movieIds": [1]}' "http://$H:7878/api/v3/command"
```

## Prowlarr (API v1)

```bash
curl -s -H "X-Api-Key: $PKEY" "http://$H:9696/api/v1/health" | jq '.[] | {type, source, message}'
curl -s -H "X-Api-Key: $PKEY" "http://$H:9696/api/v1/indexer" | jq '.[] | {id, name, enable, protocol}'

# indexers auto-disabled after failures (empty array = none currently disabled)
curl -s -H "X-Api-Key: $PKEY" "http://$H:9696/api/v1/indexerstatus" \
  | jq '.[] | {indexerId, disabledTill, initialFailure, mostRecentFailure}'

curl -s -H "X-Api-Key: $PKEY" "http://$H:9696/api/v1/indexerstats" \
  | jq '.indexers[] | {indexerName, numberOfQueries, numberOfFailedQueries, numberOfGrabs, averageResponseTime, averageGrabResponseTime}'

# the FlareSolverr proxy — reads http://172.39.0.2:8191/ live; loopback is equivalent
curl -s -H "X-Api-Key: $PKEY" "http://$H:9696/api/v1/indexerproxy" \
  | jq '.[] | {name, impl: .implementation, fields: [.fields[] | select(.name | test("host|port|url")) | {(.name): .value}]}'

curl -s -H "X-Api-Key: $PKEY" "http://$H:9696/api/v1/applications" | jq '.[] | {name, syncLevel}'   # plural!
curl -s -H "X-Api-Key: $PKEY" "http://$H:9696/api/v1/appprofile"  | jq '.[] | {name}'

# every indexer at once — bypasses the apps' decision layer
curl -s -H "X-Api-Key: $PKEY" "http://$H:9696/api/v1/search?query=inception&type=movie" \
  | jq '.[] | {title, indexer, size, seeders, protocol}'
```

`/api/v1/application` (singular) is `404`; the collection is `/api/v1/applications`. Results here but none in Radarr's interactive search means a quality-profile or rejection issue in Radarr, not an indexer issue.

```bash
# tasks and the names this instance accepts; the sync task is ApplicationIndexerSync
curl -s -H "X-Api-Key: $PKEY" "http://$H:9696/api/v1/system/task" | jq -r '.[] | .taskName'
curl -s -X POST -H "X-Api-Key: $PKEY" -H "Content-Type: application/json" \
  -d '{"name": "ApplicationIndexerSync"}' "http://$H:9696/api/v1/command"
```

## Seerr (API v1)

`GET /api/v1/status` is public; everything else needs `X-Api-Key: $EKEY`.

```bash
curl -s "http://$H:5055/api/v1/status" | jq '{version, updateAvailable, restartRequired}'
curl -s -H "X-Api-Key: $EKEY" "http://$H:5055/api/v1/request?take=25&filter=pending&sort=added" \
  | jq '.results[] | {id, status, type, media: .media.tmdbId, requestedBy: .requestedBy.displayName}'
curl -s -H "X-Api-Key: $EKEY" "http://$H:5055/api/v1/search?query=inception" | jq '.results[] | {mediaType, id, title: (.title // .name)}'
```

Request object keys: `id, status, type, media, requestedBy, createdAt, updatedAt, seasons, seasonCount, is4k, isAutoRequest, profileId, rootFolder, serverId, tags`. A request stuck at `pending` after approval is Seerr's Radarr/Sonarr connection, not the \*arr app's indexer.

## qBittorrent (API v2)

Cookie auth; no API key exists. The password is stored as a PBKDF2 hash and cannot be recovered — if it is lost, reset it in the container (`docker compose stop qbittorrent`, edit `WebUI\Password_PBKDF2` out, start) rather than trying to read it.

```bash
# qBittorrent rejects WebUI POSTs whose origin it does not trust — send the Referer
curl -s -c /tmp/qbt.jar -H "Referer: http://$H:8080" \
  --data-urlencode 'username=<WebUI\Username>' --data-urlencode 'password=<password>' \
  "http://$H:8080/api/v2/auth/login"          # prints "Ok."

curl -s -b /tmp/qbt.jar "http://$H:8080/api/v2/app/version"
curl -s -b /tmp/qbt.jar "http://$H:8080/api/v2/transfer/info" | jq '{dl_info_speed, up_info_speed, connection_status}'

curl -s -b /tmp/qbt.jar "http://$H:8080/api/v2/app/preferences" \
  | jq '{save_path, temp_path, temp_path_enabled, listen_port, current_network_interface}'

curl -s -b /tmp/qbt.jar "http://$H:8080/api/v2/torrents/info?filter=downloading" \
  | jq '.[] | {name, state, progress: (.progress * 100 | round), dlspeed, num_seeds, num_leechs, eta, category}'

curl -s -b /tmp/qbt.jar "http://$H:8080/api/v2/torrents/properties?hash=<hash>" | jq '{save_path, completion_date, total_size}'
curl -s -b /tmp/qbt.jar "http://$H:8080/api/v2/torrents/trackers?hash=<hash>"  | jq '.[] | {url, status, msg, num_peers}'
```

`save_path` proves or disproves a path-mapping theory: it must sit inside a mounted root, not in the container's writable layer.

State changes (5.x names; `pause`/`resume` are deprecated aliases):

```bash
curl -s -b /tmp/qbt.jar -d "hashes=<hash>" "http://$H:8080/api/v2/torrents/stop"
curl -s -b /tmp/qbt.jar -d "hashes=<hash>" "http://$H:8080/api/v2/torrents/start"
# destructive: deletes downloaded data
curl -s -b /tmp/qbt.jar -d "hashes=<hash>&deleteFiles=true" "http://$H:8080/api/v2/torrents/delete"
```

### Without credentials

`GET /api/v2/*` returns `403` unauthenticated. For a read-only view of the same facts, read config and namespace directly — both are readable without logging in:

```bash
# live settings: [BitTorrent] holds Session\* keys, [WebUI] holds WebUI\* keys
grep -viE 'pass|cookie|secret|token|apikey|_key' \
  media/data/qbittorrent/qBittorrent/qBittorrent.conf

# what the tunnel namespace actually listens on — compare with media/data/pia-shared/port.dat
docker exec vpn ss -lun | grep -E '41066|6881|<forwarded-port>'
```

`[WebUI] AuthSubnetWhitelist` currently whitelists `172.39.0.10/32` (Maintainerr) for passwordless access; the \*arr apps instead store credentials in their download-client config, so changing qBittorrent's password breaks Radarr, Sonarr and Lidarr until they are updated too.

## FlareSolverr

```bash
# no auth, no key
curl -s -X POST -H 'Content-Type: application/json' -d '{"cmd":"sessions.list"}' "http://$H:8191/v1"

# a real solve, to test a Cloudflare-protected indexer end to end
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"cmd":"request.get","url":"https://example.com","maxTimeout":60000}' "http://$H:8191/v1" | jq '{status, message}'
```

Published on 8191 because it shares the `vpn` namespace; from Prowlarr the working URL is `http://172.39.0.2:8191/` (loopback is the same namespace).

## Bazarr (unversioned `/api`)

Header `X-API-KEY`. Verified endpoints and shapes:

```bash
curl -s -H "X-API-KEY: $BKEY" "http://$H:6767/api/system/status"
# {"data": {"bazarr_version": "1.6.2", "sonarr_version": "...", "radarr_version": "...",
#           "sonarr_signalr": "LIVE", "database_engine": "Sqlite ...", ...}}

curl -s -H "X-API-KEY: $BKEY" "http://$H:6767/api/badges"
# {"episodes": 175, "movies": 4, "providers": 1, "status": 0, "sonarr_signalr": "LIVE", ...}

curl -s -H "X-API-KEY: $BKEY" "http://$H:6767/api/movies/wanted?start=0&length=10"
# {"data": [{"title": "...", "radarrId": 251, "missing_subtitles": [{"name": "Portuguese (Brazil)", "code2": "pb"}], ...}], "total": n}
curl -s -H "X-API-KEY: $BKEY" "http://$H:6767/api/episodes/wanted?start=0&length=10"
curl -s -H "X-API-KEY: $BKEY" "http://$H:6767/api/providers"    # enabled subtitle providers
curl -s -H "X-API-KEY: $BKEY" "http://$H:6767/api/languages"
```

`providers` is the first thing to check on "Bazarr finds nothing" — a count of one is the usual answer. `signalr: LIVE` in `system/status` is the cheapest proof that Bazarr's Sonarr/Radarr links are up. A bad key returns `401` with `"The server could not verify that you are authorized to access the URL requested."`.

## Maintainerr

No stable public API — `GET /api/status` is `404`. Use the UI at `maintainerr.lexcode.dev`; the container healthcheck `/opt/app/healthcheck.sh` is the programmatic signal via `docker compose ps`. Deep detail: `media/README.md` → *Maintainerr*.

## Chaptarr (API v1)

> Paths below are taken from Chaptarr's published OpenAPI document
> (`src/Chaptarr.Api.V1/openapi.json`, 2026-11) and from the Dockerfile's
> `EXPOSE 8789` — they have **not** yet been exercised against the running
> stack. Treat a surprising response here as unverified rather than broken.

Readarr lineage, so v1 and book vocabulary: `/api/v3/*` is `404`, and the
entities are `author` and `book`. Port 8789, container `chaptarr`.

```bash
H=192.168.0.24
CKEY=$(grep -oP '(?<=<ApiKey>)[^<]+' media/data/chaptarr/config.xml)

curl -s "http://$H:8789/ping"                       # liveness, no key
curl -s -H "X-Api-Key: $CKEY" "http://$H:8789/api/v1/system/status" | jq '{version, appName, databaseType}'

# root folders — is the book library a real mount, or an empty local dir?
curl -s -H "X-Api-Key: $CKEY" "http://$H:8789/api/v1/rootfolder" | jq '.[] | {path, accessible, freeSpace}'

# health, queue and wanted list: the same triage ladder as Radarr/Sonarr
curl -s -H "X-Api-Key: $CKEY" "http://$H:8789/api/v1/health" | jq '.[] | {type, source, message}'
curl -s -H "X-Api-Key: $CKEY" "http://$H:8789/api/v1/queue" | jq '.records[] | {title, status, trackedDownloadState, errorMessage}'
curl -s -H "X-Api-Key: $CKEY" "http://$H:8789/api/v1/wanted/missing" | jq '.totalRecords'

# what the app thinks its indexers and download client are
curl -s -H "X-Api-Key: $CKEY" "http://$H:8789/api/v1/config/indexer" | jq '{maximumSize, minimumAge}'
curl -s -H "X-Api-Key: $CKEY" "http://$H:8789/api/v1/downloadclient" | jq '.[] | {name, implementation, enable}'
```

Empty metadata (no author, title or cover on a searched book) is the metadata
provider, not the indexer: check Settings → Metadata, and note Hardcover needs
an API token. Empty search results across every indexer are the same cause as
elsewhere in the stack — film/TV trackers carry no books.

## slskd (API v0)

Header `X-API-Key`. Keys are added under `web.authentication.api_keys` in
`media/data/slskd/slskd.yml` (or the same document via System → Options → Edit); `role:
readwrite` covers everything below. Reaches the `vpn` namespace at `http://172.39.0.2:5030`,
or `http://<host>:5030` off-host; `http://slskd:5030` does not resolve.

Verified live against this stack (2026-11): `application`, `searches`, `transfers/downloads`
and `session` answer `200` with a `readwrite` key; `server` and `options` answer `403` at that
role. Response field names are verified only where noted — confirm with a `GET` before
scripting anything destructive.

```bash
SLS=http://172.39.0.2:5030
SLSKEY=<key from data/slskd/slskd.yml>

# readiness in one call: version plus the Soulseek login state. This is what a consumer
# checks before searching; `session` returns 200 with an empty body and proves nothing.
curl -s -H "X-API-Key: $SLSKEY" "$SLS/api/v0/application" | jq '{v: .version.current, state: .server.state, connected: .server.isConnected}'
# {"v":"0.26.2.0","state":"Connected, LoggedIn","connected":true}

# /api/v0/server is administrator-only (403 at readwrite) — don't script against it
curl -s -o /dev/null -w '%{http_code}\n' -H "X-API-Key: $SLSKEY" "$SLS/api/v0/server"

# active searches, and the peer responses for one of them
curl -s -H "X-API-Key: $SLSKEY" "$SLS/api/v0/searches"
curl -s -H "X-API-Key: $SLSKEY" "$SLS/api/v0/searches/<id>/responses"

# queues, positions and failures — the download-side equivalent of an *arr queue
curl -s -H "X-API-Key: $SLSKEY" "$SLS/api/v0/transfers/downloads"
curl -s -H "X-API-Key: $SLSKEY" "$SLS/api/v0/transfers/downloads/<username>"

# writes: POST /api/v0/searches, POST /api/v0/transfers/downloads/<username>,
# DELETE /api/v0/transfers/downloads/<username>/<id>  — all change network or disk state
```

Options live at `/api/v0/options` (upstream documents `PATCH` there for live settings). The
UI is the supported way to edit them; prefer it over scripts.

## Beets

No HTTP API. `./beets/beet.sh stats | ls <query> | missing | dupes | check | retry <path>`, and `media/data/beets/import.log` records what each import decided.
