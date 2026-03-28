# Torrent Search API Spec

Base URL on your LAN:

- `http://<server-ip>:8790`

Current example:

- `http://192.168.1.8:8790`

Local web UI:

- `http://127.0.0.1:8789/`

## Overview

This API is intended for an Apple TV client.

Flow:

1. Search torrents
2. Show results
3. User chooses a result
4. Client sends the selected `resultId` back to the server
5. Server queues the download through `aria2`
6. Client polls download status by `gid`
7. If the original request was a magnet link, the API may transparently follow aria2 from metadata download to content download

## Authentication

No API auth is implemented yet.
This is acceptable only for a trusted LAN during development.

## Runtime Notes

- The current downloader is `aria2`
- Downloads are stored in `C:\Users\arnyb\Downloads`
- The API returns the effective aria2 download directory and primary file path in download status responses

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
    "configured": true
  }
}
```

Legacy compatibility:

- `GET /api/health` also exists and returns a smaller health payload

### `GET /api/v1/system`

Returns the current hostname, detected LAN IPv4 addresses, and the preferred LAN API URL.

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
- Treat `sizeBytes`, `seeders`, and `publishedAt` as optional

Legacy compatibility:

- `GET /api/search?q=<query>` also exists and returns the raw provider search payload

### `POST /api/v1/downloads`

Queues a selected torrent in the configured downloader.

Accepted JSON body fields:

- `resultId`
- `sourceUrl`
- `downloadUrl`
- `magnetUri`

At least one is required.

Example request:

```json
{
  "resultId": "1b9d9bd9d61f4e2f9bbca8ce6ff6fd7f"
}
```

Example response:

```json
{
  "status": "ok",
  "message": "Download queued.",
  "downloader": "aria2",
  "gid": "2089b05ecca3d829"
}
```

Status codes:

- `202 Accepted` when queued successfully
- `400 Bad Request` for missing or invalid body
- `502 Bad Gateway` when the downloader is unavailable or returns an error

### `GET /api/v1/downloads/{gid}`

Returns the current status of a queued aria2 download.

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
    "completedBytes": 524288000,
    "downloadSpeedBytesPerSecond": 3145728,
    "directory": "C:\\Users\\arnyb\\Downloads",
    "primaryPath": "C:\\Users\\arnyb\\Downloads\\ubuntu.iso",
    "name": "ubuntu.iso",
    "metadataGid": "2089b05ecca3d829",
    "followedBy": [
      "7532af166cc96d59"
    ]
  }
}
```

Notes for client:

- `requestedGid` is the `gid` originally returned by `POST /api/v1/downloads`
- `gid` is the effective aria2 task currently representing the actual download
- For direct torrents, `requestedGid` and `gid` may be the same
- For magnet links, aria2 may first create a metadata task, then spawn a content task
- When that happens:
  - `metadataGid` is the metadata stage
  - `gid` points at the content stage once available
  - `followedBy` contains the next aria2 `gid`
- If `primaryPath` starts with `[METADATA]`, the download is still in metadata phase
- If `primaryPath` is a real file path, the content download has started

## Suggested Apple TV client model

### SearchResult

```json
{
  "title": "string",
  "indexer": "string",
  "sizeBytes": 0,
  "seeders": 0,
  "leechers": 0,
  "publishedAt": "ISO-8601 string or null",
  "protocol": "string or null",
  "resultId": "string",
  "hasSource": true
}
```

### QueuedDownload

```json
{
  "status": "ok",
  "message": "Download queued.",
  "downloader": "aria2",
  "gid": "string"
}
```

### DownloadStatus

```json
{
  "status": "ok",
  "downloader": "aria2",
  "download": {
    "requestedGid": "string",
    "gid": "string",
    "state": "active|waiting|paused|complete|error|removed",
    "infoHash": "string or null",
    "totalBytes": 0,
    "completedBytes": 0,
    "downloadSpeedBytesPerSecond": 0,
    "directory": "string or null",
    "primaryPath": "string or null",
    "name": "string or null",
    "metadataGid": "string or null",
    "followedBy": [
      "string"
    ]
  }
}
```

### Suggested client logic for phase

- Metadata phase:
  - `metadataGid != null`
  - or `primaryPath` starts with `[METADATA]`
- Content phase:
  - `primaryPath` points to a real filesystem path
  - or `gid != requestedGid`

## Error Notes

- `GET /api/v1/search` returns `400 Bad Request` if `q` is missing
- `POST /api/v1/downloads` returns `400 Bad Request` for invalid JSON or when none of `resultId`, `sourceUrl`, `downloadUrl`, or `magnetUri` is provided
- `GET /api/v1/downloads/{gid}` returns `502 Bad Gateway` if aria2 is unreachable or returns an error
