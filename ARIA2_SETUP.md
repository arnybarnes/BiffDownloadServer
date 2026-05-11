# aria2 Setup

## Recommendation

Use `aria2`.

Why it fits this project:

- It is a real command-line downloader
- It supports BitTorrent and magnet links
- It exposes JSON-RPC, which makes server-side control straightforward
- It is a much better match for an Apple TV -> Python API -> downloader flow than trying to automate a desktop torrent GUI

Official sources:

- https://aria2.github.io/
- https://aria2.github.io/manual/en/html/index.html

## What to install

Install the Windows build of `aria2`, then make sure `aria2c.exe` is available.

## Run aria2 with RPC enabled

Example PowerShell command:

```powershell
aria2c `
  --enable-rpc `
  --rpc-listen-all=false `
  --rpc-listen-port=6800 `
  --rpc-secret=change-me `
  --dir="C:\Users\arnyb\Downloads\torrents"
```

Notes:

- `--enable-rpc` turns on the JSON-RPC server
- `--rpc-listen-all=false` keeps RPC local-only, which is what you want because your Python API is the LAN-facing layer
- `--rpc-listen-port=6800` matches the project config
- `--rpc-secret` should be set and copied into `config.local.json`

## Project config

Update [C:\Users\arnyb\Documents\torrentsearch\config.local.json](C:\Users\arnyb\Documents\torrentsearch\config.local.json):

```json
"downloader": "aria2",
"downloaders": {
  "aria2": {
    "rpc_url": "http://127.0.0.1:6800/jsonrpc",
    "secret": "change-me",
    "download_dir": "C:\\Users\\arnyb\\Downloads\\torrents"
  }
}
```

## How the app uses it

- Apple TV calls the Python API
- Python API calls aria2 JSON-RPC locally
- aria2 downloads the torrent on this PC

## Endpoints related to aria2

- `POST /api/v1/downloads`
- `GET /api/v1/downloads/{gid}`
