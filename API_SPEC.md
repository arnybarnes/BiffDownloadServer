# Torrent Search API Spec

Base URL on your LAN:

- `http://<server-ip>:8790`

Current example:

- `http://192.168.1.8:8790`

Local web UI:

- `http://127.0.0.1:8789/`

## Overview

This API is intended for the Apple TV client.

Current download flow:

1. Search torrents.
2. Show results.
3. User chooses a result.
4. User chooses a destination folder and optional rename target.
5. Client queues the download.
6. Server downloads the entire torrent into `C:\Users\arnyb\Downloads\temp`.
7. Client polls status by `gid`.
8. When `completedBytes >= totalBytes`, the Apple TV client calls the explicit finalize endpoint.
9. Server copies the selected video file from `temp` to the chosen destination folder.
10. If the user wants to remove the leftover torrent data from `temp`, the Apple TV client calls the explicit cleanup endpoint.

Important behavior:

- The server does not auto-move files when aria2 reports a terminal status.
- The server does not auto-delete temp files after copy.
- For some torrents, aria2 may stay `active` after 100% because it is still seeding. Clients must key off byte completion, not only aria2 `state == "complete"`.

## Authentication

No API auth is implemented yet.
This is acceptable only for a trusted LAN during development.

## Runtime Notes

- Downloader: `aria2`
- Download root: `C:\Users\arnyb\Downloads`
- Temp staging root: `C:\Users\arnyb\Downloads\temp`
- The API may transparently follow aria2 from a magnet metadata task to the effective content task

## Endpoints

### `GET /api/v1/health`

Returns server health and whether the search provider and downloader are configured.

Example response:

```json
{
  "status": "ok",
  "service": "torrentsearch-api",
  "version": "v1",
  "provider": {
    "name": "prowlarr",
    "configured": true
  },
  "downloader": {
    "name": "aria2",
    "configured": true,
    "downloadRoot": "C:\\Users\\arnyb\\Downloads"
  }
}
```

Legacy compatibility:

- `GET /api/health` also exists and returns a smaller health payload

### `GET /api/v1/system`

Returns the current hostname, detected LAN IPv4 addresses, the preferred LAN API URL, and whether restart is supported.

Example response:

```json
{
  "status": "ok",
  "system": {
    "hostname": "DESKTOP-SB0Q7M3",
    "lanIPv4": [
      "10.27.180.163",
      "192.168.1.8"
    ],
    "preferredLanIp": "192.168.1.8",
    "restartSupported": true,
    "web": {
      "host": "127.0.0.1",
      "port": 8789,
      "localUrl": "http://127.0.0.1:8789/"
    },
    "api": {
      "host": "0.0.0.0",
      "port": 8790,
      "localUrl": "http://127.0.0.1:8790",
      "lanUrl": "http://192.168.1.8:8790"
    }
  }
}
```

### `POST /api/v1/system/restart`

Schedules the same local restart flow used by `start-local.ps1`.

Behavior:

- Windows-only
- Launches `start-local.ps1` in a detached process
- The current request should return before the local services are recycled

Example response:

```json
{
  "status": "restarting",
  "message": "Local restart scheduled via start-local.ps1."
}
```

Status codes:

- `202 Accepted` when restart was scheduled
- `500 Internal Server Error` if the restart process could not be launched
- `501 Not Implemented` if restart is unavailable on the current host

### `GET /api/v1/services/mac-api`

Returns the current registry entry for the Mac subtitle helper service plus a live probe of its `/health` endpoint.

Example response — online:

```json
{
  "status": "ok",
  "service": {
    "name": "mac-api",
    "registered": true,
    "online": true,
    "heartbeatFresh": true,
    "lastSeen": "2026-05-15T22:10:00Z",
    "lastSeenAgeSeconds": 3.2,
    "staleAfterSeconds": 45.0,
    "hostname": "Arnolds-Mac-mini",
    "instanceId": "mac-api-20260515-221000",
    "version": "1.0.0",
    "baseUrl": "http://192.168.1.4:8800",
    "healthUrl": "http://192.168.1.4:8800/health",
    "port": 8800,
    "addresses": [
      "192.168.1.4"
    ],
    "meta": {
      "role": "subtitle-generator"
    },
    "healthReachable": true,
    "health": {
      "status": "ok",
      "service": "mac-api",
      "version": "1.0.0"
    },
    "healthError": null
  }
}
```

Example response — nothing registered yet:

```json
{
  "status": "degraded",
  "service": {
    "name": "mac-api",
    "registered": false,
    "online": false,
    "heartbeatFresh": false
  }
}
```

Notes:

- This endpoint is the stable Apple TV check for whether AI subtitle generation is available
- `online` is based on an active probe of the registered `healthUrl` when possible
- Heartbeats are considered stale after `45` seconds
- `status` is `"degraded"` when the helper is missing or not healthy

Status codes:

- `200 OK`

### `POST /api/v1/services/register`

Registers a helper service on the LAN. This is primarily used by the Mac subtitle helper when it starts.

Request body:

```json
{
  "service": "mac-api",
  "hostname": "Arnolds-Mac-mini",
  "instanceId": "mac-api-20260515-221000",
  "baseUrl": "http://192.168.1.4:8800",
  "healthUrl": "http://192.168.1.4:8800/health",
  "port": 8800,
  "version": "1.0.0",
  "addresses": [
    "192.168.1.4"
  ],
  "meta": {
    "role": "subtitle-generator"
  }
}
```

Accepted fields:

- `service`: required service name, for example `"mac-api"`
- `hostname`: required machine hostname
- `baseUrl`: optional full helper base URL
- `healthUrl`: optional full helper health URL
- `port`: optional TCP port
- `instanceId`: optional instance identifier for the running helper process
- `version`: optional helper version string
- `addresses`: optional list of LAN IP addresses
- `meta`: optional object for helper-specific metadata

Notes:

- At least one of `baseUrl` or `healthUrl` must be provided
- If `healthUrl` is omitted and `baseUrl` is present, the API assumes `{baseUrl}/health`

Example response:

```json
{
  "status": "ok",
  "message": "Service registered.",
  "service": {
    "name": "mac-api",
    "hostname": "Arnolds-Mac-mini",
    "instanceId": "mac-api-20260515-221000",
    "baseUrl": "http://192.168.1.4:8800",
    "healthUrl": "http://192.168.1.4:8800/health",
    "lastSeen": "2026-05-15T22:10:00Z"
  }
}
```

Status codes:

- `200 OK`
- `400 Bad Request` if required fields are missing or invalid

### `POST /api/v1/services/heartbeat`

Refreshes the last-seen timestamp for a registered helper service. The accepted request body is the same as `POST /api/v1/services/register`.

Example response:

```json
{
  "status": "ok",
  "message": "Service heartbeat recorded.",
  "service": {
    "name": "mac-api",
    "hostname": "Arnolds-Mac-mini",
    "instanceId": "mac-api-20260515-221000",
    "baseUrl": "http://192.168.1.4:8800",
    "healthUrl": "http://192.168.1.4:8800/health",
    "lastSeen": "2026-05-15T22:10:15Z"
  }
}
```

Status codes:

- `200 OK`
- `400 Bad Request` if required fields are missing or invalid

### `GET /api/v1/download-folders`

Returns the destination folders available under the configured download root.

Example response:

```json
{
  "status": "ok",
  "root": "C:\\Users\\arnyb\\Downloads",
  "count": 3,
  "folders": [
    {
      "key": "",
      "name": "Default",
      "relativePath": "",
      "absolutePath": "C:\\Users\\arnyb\\Downloads",
      "isDefault": true
    },
    {
      "key": "ForAllMankindSeason5",
      "name": "ForAllMankindSeason5",
      "relativePath": "ForAllMankindSeason5",
      "absolutePath": "C:\\Users\\arnyb\\Downloads\\ForAllMankindSeason5",
      "isDefault": false
    }
  ]
}
```

### `GET /api/v1/disk`

Returns disk space information for the drive containing the download root.

Example response:

```json
{
  "status": "ok",
  "disk": {
    "path": "C:\\Users\\arnyb\\Downloads",
    "totalBytes": 1000202039296,
    "usedBytes": 750151290880,
    "freeBytes": 250050748416,
    "percentUsed": 74.9
  }
}
```

Notes:

- `path` is the configured download root
- `percentUsed` is rounded to one decimal place
- All byte values reflect the whole drive/volume, not just the download root folder

Status codes:

- `200 OK`

### `GET /api/v1/search?q=<query>`

Searches the configured provider.

Example:

```http
GET /api/v1/search?q=ubuntu
```

Example response:

```json
{
  "status": "ok",
  "query": "ubuntu",
  "message": "Found 25 result(s) from Prowlarr.",
  "provider": "prowlarr",
  "count": 25,
  "items": [
    {
      "resultId": "1b9d9bd9d61f4e2f9bbca8ce6ff6fd7f",
      "title": "Ubuntu 22.04 LTS",
      "indexer": "The Pirate Bay",
      "sizeBytes": 3654957056,
      "seeders": 31,
      "leechers": 3,
      "publishedAt": "2022-05-18T12:33:51Z",
      "protocol": "torrent",
      "hasSource": true
    }
  ]
}
```

Notes for client:

- Use `resultId` when the user picks a search result
- Do not expect provider download URLs in the search response
- The server intentionally hides provider-specific source URLs and API keys from the Apple TV client
- Treat `sizeBytes`, `seeders`, `publishedAt`, and `hasSource` as optional

Legacy compatibility:

- `GET /api/search?q=<query>` also exists and returns the raw provider search payload

### `POST /api/v1/downloads`

Queues a selected torrent in aria2.

Accepted JSON body fields:

- One of:
  - `resultId`
  - `sourceUrl`
  - `downloadUrl`
  - `magnetUri`
- Optional:
  - `folder`: direct child folder key returned by `GET /api/v1/download-folders`
  - `fileName`: requested output name without a path; extension is optional

Important behavior:

- The entire torrent is downloaded into `temp`
- The server records the chosen destination folder and requested rename target
- The server does not ask aria2 to prune the torrent down to a single file
- The server does not move or delete anything at queue time

Example request:

```json
{
  "resultId": "1b9d9bd9d61f4e2f9bbca8ce6ff6fd7f",
  "folder": "ForAllMankindSeason5",
  "fileName": "s05e03"
}
```

Example response:

```json
{
  "status": "ok",
  "message": "Download queued.",
  "downloader": "aria2",
  "gid": "2089b05ecca3d829",
  "directory": "C:\\Users\\arnyb\\Downloads\\ForAllMankindSeason5",
  "stagingDirectory": "C:\\Users\\arnyb\\Downloads\\temp",
  "fileName": "s05e03.mkv"
}
```

Status codes:

- `202 Accepted` when queued successfully
- `400 Bad Request` for missing or invalid body
- `502 Bad Gateway` when the downloader is unavailable or returns an error

### `GET /api/v1/downloads/{gid}`

Returns the current status of a queued aria2 download plus server-side selection, finalization, and cleanup state.

Example response:

```json
{
  "status": "ok",
  "downloader": "aria2",
  "download": {
    "requestedGid": "2089b05ecca3d829",
    "gid": "7532af166cc96d59",
    "state": "active",
    "infoHash": "abc123",
    "totalBytes": 3654957056,
    "completedBytes": 3654957056,
    "downloadSpeedBytesPerSecond": 0,
    "directory": "C:\\Users\\arnyb\\Downloads\\ForAllMankindSeason5",
    "primaryPath": "C:\\Users\\arnyb\\Downloads\\temp\\For All Mankind\\s05e03.mkv",
    "stagingDirectory": "C:\\Users\\arnyb\\Downloads\\temp",
    "name": "For All Mankind",
    "metadataGid": "2089b05ecca3d829",
    "followedBy": [
      "7532af166cc96d59"
    ],
    "fileSelection": {
      "state": "selected",
      "message": "Entire torrent stays in temp; the selected video will be copied after the download reaches 100%.",
      "selectedFile": {
        "index": "5",
        "name": "s05e03.mkv",
        "path": "C:\\Users\\arnyb\\Downloads\\temp\\For All Mankind\\s05e03.mkv",
        "sizeBytes": 3654957056
      },
      "renameTarget": {
        "requestedName": "s05e03",
        "fileName": "s05e03.mkv",
        "appliesToIndex": "5"
      }
    },
    "finalization": {
      "state": "not_requested",
      "message": "Download data is complete. Waiting for the Apple TV app to request the final copy.",
      "mode": null,
      "stagingDirectory": "C:\\Users\\arnyb\\Downloads\\temp",
      "targetDirectory": "C:\\Users\\arnyb\\Downloads\\ForAllMankindSeason5",
      "sourcePath": null,
      "destinationPath": null,
      "totalBytes": null,
      "completedBytes": null,
      "finalPath": null
    },
    "cleanup": {
      "state": "not_requested",
      "message": null,
      "deletedPaths": null
    }
  }
}
```

Notes for client:

- `requestedGid` is the `gid` originally returned by `POST /api/v1/downloads`
- `gid` is the effective aria2 task currently representing the actual download
- For direct torrents, `requestedGid` and `gid` may be the same
- For magnet links, aria2 may first create a metadata task, then spawn a content task
- If `completedBytes >= totalBytes`, the content is ready for explicit finalization even if `state` is still `active`
- `directory` is the user-selected destination folder, not the temp staging folder
- `primaryPath` is the current working file path until finalization completes, then becomes the final copied path

State values returned inside `download`:

- `fileSelection.state`:
  - `pending`
  - `selected`
  - `not_requested`
- `finalization.state`:
  - `not_requested`
  - `queued`
  - `in_progress`
  - `completed`
  - `error`
- `cleanup.state`:
  - `not_requested`
  - `in_progress`
  - `completed`
  - `error`

### `POST /api/v1/downloads/{gid}/finalize`

Starts the explicit copy from `temp` to the selected destination folder.

Behavior:

- Requires `completedBytes >= totalBytes`
- Chooses the selected video file from the torrent contents
- Applies the requested rename target if one was provided
- Copies the selected video into the destination folder
- Leaves the original torrent data in `temp`

Example response while copy is starting:

```json
{
  "status": "ok",
  "message": "Final copy requested.",
  "downloader": "aria2",
  "download": {
    "finalization": {
      "state": "queued",
      "message": "Queued selected video for copy into the destination folder.",
      "mode": "copy",
      "sourcePath": "C:\\Users\\arnyb\\Downloads\\temp\\For All Mankind\\s05e03.mkv",
      "destinationPath": "C:\\Users\\arnyb\\Downloads\\ForAllMankindSeason5\\s05e03.mkv",
      "totalBytes": 3654957056,
      "completedBytes": 0,
      "finalPath": null
    }
  }
}
```

Status codes:

- `202 Accepted` when copy was queued
- `200 OK` if copy was already running or already completed
- `409 Conflict` if the download is not ready or the source file could not be resolved
- `500 Internal Server Error` if the destination could not be prepared
- `502 Bad Gateway` if aria2 could not be queried

### `POST /api/v1/downloads/{gid}/cleanup`

Deletes the temp torrent data for a previously finalized download.

Behavior:

- Manual only; never triggered automatically
- Intended to be called after finalization has completed
- Stops/removes the aria2 task when possible
- Deletes the download's top-level temp files or temp folder entries
- Returns cleanup state inside the normal `download` payload

Example response:

```json
{
  "status": "ok",
  "message": "Temp torrent files deleted.",
  "downloader": "aria2",
  "download": {
    "cleanup": {
      "state": "completed",
      "message": "Temp torrent files deleted.",
      "deletedPaths": [
        "C:\\Users\\arnyb\\Downloads\\temp\\For All Mankind"
      ]
    }
  }
}
```

Important note for clients:

- After successful cleanup, the server attempts to remove the aria2 task/result
- Clients should use the `POST /cleanup` response as the final cleanup state
- Do not rely on later `GET /api/v1/downloads/{gid}` calls continuing to succeed after cleanup

Status codes:

- `200 OK` with `download.cleanup.state` describing the result
- `404 Not Found` for an unknown tracked download id
- `502 Bad Gateway` if aria2 could not be queried before cleanup started

### `GET /api/v1/files`

Lists files and folders inside the download root. Pass an optional `path` query parameter to browse a subdirectory (relative to the download root).

Example — list root:

```http
GET /api/v1/files
```

Example — list a subfolder:

```http
GET /api/v1/files?path=ForAllMankindSeason5
```

Example response:

```json
{
  "status": "ok",
  "root": "C:\\Users\\arnyb\\Downloads",
  "path": "ForAllMankindSeason5",
  "absolutePath": "C:\\Users\\arnyb\\Downloads\\ForAllMankindSeason5",
  "count": 2,
  "entries": [
    {
      "name": "Extras",
      "relativePath": "ForAllMankindSeason5\\Extras",
      "isDirectory": true,
      "sizeBytes": null,
      "modifiedAt": "2026-04-10T18:22:00Z"
    },
    {
      "name": "s05e03.mkv",
      "relativePath": "ForAllMankindSeason5\\s05e03.mkv",
      "isDirectory": false,
      "sizeBytes": 3654957056,
      "modifiedAt": "2026-04-10T18:22:00Z"
    }
  ]
}
```

Notes:

- Entries are sorted: directories first, then files, both alphabetically
- `sizeBytes` is `null` for directories
- `modifiedAt` is UTC ISO 8601
- `path` in the response is empty string when listing the root

Status codes:

- `200 OK`
- `400 Bad Request` if `path` escapes the download root or points to a file
- `404 Not Found` if the path does not exist

### `POST /api/v1/files/delete`

Deletes a file or folder (recursively) within the download root.

Request body:

```json
{
  "path": "ForAllMankindSeason5\\s05e03.mkv"
}
```

Example response:

```json
{
  "status": "ok",
  "message": "Deleted: s05e03.mkv",
  "deletedPath": "ForAllMankindSeason5\\s05e03.mkv"
}
```

Status codes:

- `200 OK`
- `400 Bad Request` if the path escapes the root or targets the root itself
- `404 Not Found` if the path does not exist
- `500 Internal Server Error` if the deletion failed

### `POST /api/v1/files/move`

Moves a file or folder to a different directory within the download root. The item keeps its name; if a name collision occurs the server appends ` (2)`, ` (3)`, etc.

Request body:

```json
{
  "source": "ForAllMankindSeason5\\s05e03.mkv",
  "destination": "Movies"
}
```

- `source`: relative path of the file or folder to move
- `destination`: relative path of the **target directory** (must already exist)

Example response:

```json
{
  "status": "ok",
  "message": "Moved to: s05e03.mkv",
  "sourcePath": "ForAllMankindSeason5\\s05e03.mkv",
  "destinationPath": "Movies\\s05e03.mkv"
}
```

Status codes:

- `200 OK`
- `400 Bad Request` if either path is invalid, or destination is not an existing directory
- `404 Not Found` if source does not exist
- `500 Internal Server Error` if the move failed

### `POST /api/v1/files/rename`

Renames a file or folder in place. The new name must not contain path separators.

Request body:

```json
{
  "path": "ForAllMankindSeason5\\s05e03.mkv",
  "name": "For All Mankind S05E03.mkv"
}
```

Example response:

```json
{
  "status": "ok",
  "message": "Renamed to: For All Mankind S05E03.mkv",
  "oldPath": "ForAllMankindSeason5\\s05e03.mkv",
  "newPath": "ForAllMankindSeason5\\For All Mankind S05E03.mkv",
  "newName": "For All Mankind S05E03.mkv"
}
```

Status codes:

- `200 OK`
- `400 Bad Request` if the name is invalid, missing, or already taken at that location
- `404 Not Found` if the path does not exist
- `500 Internal Server Error` if the rename failed

### `POST /api/v1/files/create-folder`

Creates a new folder inside a directory within the download root. The `path` field is the directory currently being browsed (as returned by `GET /api/v1/files`).

Request body:

```json
{
  "path": "ForAllMankindSeason5",
  "name": "Extras"
}
```

- `path`: relative path of the parent directory. Omit or pass empty string to create in the download root.
- `name`: name of the new folder. Must not contain path separators or invalid Windows characters.

Example response:

```json
{
  "status": "ok",
  "message": "Created: Extras",
  "path": "ForAllMankindSeason5\\Extras"
}
```

Status codes:

- `200 OK`
- `400 Bad Request` if the name is missing/invalid, the parent path is not a directory, or a folder with that name already exists
- `404 Not Found` if the parent path does not exist
- `500 Internal Server Error` if the folder could not be created

### `POST /api/v1/subtitles/download`

Downloads an external `.srt` subtitle for a video file using OpenSubtitles (legacy XML-RPC provider). Credentials are read from `config.local.json` under `subtitles.opensubtitles`.

This is the existing "download an already published subtitle" path. It is separate from `POST /api/v1/subtitles/generate`, which creates new subtitles through the Mac AI helper.

Request body:

```json
{
  "path": "From-season4\\s04e01.mkv",
  "name": "from s04e01",
  "language": "en"
}
```

- `path`: relative path of the video file within the download root
- `name`: hint passed to subliminal's `-n` flag for show/episode identification (e.g. `"from s04e01"`)
- `language`: IETF language code (default: `"en"`)

The subtitle is saved alongside the video as `{stem}.{language}.srt` (e.g. `s04e01.en.srt`).

Example response — found:

```json
{
  "status": "ok",
  "message": "Downloaded 1 subtitle.",
  "subtitlePath": "From-season4\\s04e01.en.srt"
}
```

Example response — not found:

```json
{
  "status": "ok",
  "message": "No subtitle found.",
  "subtitlePath": null
}
```

Status codes:

- `200 OK` in both found and not-found cases
- `400 Bad Request` if `path` or `name` is missing/invalid, or credentials are not configured
- `404 Not Found` if the video file does not exist
- `500 Internal Server Error` if subliminal fails or times out

### `POST /api/v1/subtitles/merge`

Merges an external subtitle file into a video file using ffmpeg. The subtitle is added as a default selectable track; the original video is not modified. Output is written alongside the video as `{stem}_with_subs{ext}` (e.g. `s04e01_with_subs.mkv`). If that name is already taken, a ` (2)` suffix is appended.

Request body:

```json
{
  "videoPath": "From-season4\\s04e01.mkv",
  "subtitlePath": "From-season4\\s04e01.en.srt"
}
```

Example response:

```json
{
  "status": "ok",
  "message": "Subtitle merged.",
  "outputPath": "From-season4\\s04e01_with_subs.mkv"
}
```

Status codes:

- `200 OK`
- `400 Bad Request` if paths are missing or escape the download root
- `404 Not Found` if the video or subtitle file does not exist
- `500 Internal Server Error` if ffmpeg fails or times out

### `POST /api/v1/subtitles/generate`

Generates a new subtitle file by sending extracted audio to the registered Mac subtitle helper, then muxes the generated subtitles into a copy of the video.

Request body:

```json
{
  "videoPath": "From-season4\\s04e01.mkv",
  "language": "en"
}
```

- `videoPath`: relative path of the source video inside the download root
- `language`: optional requested transcription language. Omit or pass empty string to let the Mac helper auto-detect it

Compatibility note:

- `path` is also accepted as an alias for `videoPath`, but new clients should use `videoPath`

Behavior:

- Requires an online helper from `GET /api/v1/services/mac-api`
- Extracts temporary mono 16 kHz WAV audio from the source video
- Sends the audio to the Mac helper service
- Saves the returned subtitle beside the video as `{stem}.generated.srt`
- Writes a new output copy beside the video as `{stem}_generated_subs{ext}`
- `.mkv` sources produce `{stem}_generated_subs.mkv`
- `.mp4` sources also produce `{stem}_generated_subs.mkv`
- The generated subtitle track is named `AI Generated`
- Existing tracks are preserved while the new generated subtitle track is added
- Other containers are rejected

Example response:

```json
{
  "status": "ok",
  "message": "Generated subtitles and muxed them into a copy.",
  "subtitlePath": "From-season4\\s04e01.generated.srt",
  "outputPath": "From-season4\\s04e01_generated_subs.mkv",
  "macService": {
    "hostname": "Arnolds-Mac-mini",
    "baseUrl": "http://192.168.1.4:8800",
    "healthUrl": "http://192.168.1.4:8800/health",
    "version": "1.0.0"
  },
  "transcription": {
    "requestedLanguage": "en",
    "detectedLanguage": "en",
    "segmentCount": 48,
    "model": "mlx-community/whisper-small-mlx"
  }
}
```

Status codes:

- `200 OK`
- `400 Bad Request` if the request is invalid, the path escapes the download root, or the container is unsupported
- `404 Not Found` if the video file does not exist
- `502 Bad Gateway` if the Mac helper cannot be reached or returns an HTTP error
- `500 Internal Server Error` if local extraction, local muxing, or helper-side processing fails

## Suggested Apple TV Client Rules

- Search with `GET /api/v1/search`
- Load folders with `GET /api/v1/download-folders`
- Queue with `POST /api/v1/downloads`
- Poll with `GET /api/v1/downloads/{gid}`
- When `completedBytes >= totalBytes` and `finalization.state == "not_requested"`, call `POST /api/v1/downloads/{gid}/finalize`
- Keep showing status while `finalization.state` is `queued` or `in_progress`
- Only show the final success state once `finalization.state == "completed"`
- Only delete temp files if the user explicitly requests it by calling `POST /api/v1/downloads/{gid}/cleanup`
- For AI-generated subtitles, check `GET /api/v1/services/mac-api` before calling `POST /api/v1/subtitles/generate`
