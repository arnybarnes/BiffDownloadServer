# Torrent Search Starter

This project is a simple starter for a torrent search web page backed by a Python API.
The goal is to keep one backend contract that can later be reused by a Swift Apple TV app.

## Local config file

The app now reads local settings from [C:\Users\arnyb\Documents\torrentsearch\config.local.json](C:\Users\arnyb\Documents\torrentsearch\config.local.json).

- This file is ignored by git via [C:\Users\arnyb\Documents\torrentsearch\.gitignore](C:\Users\arnyb\Documents\torrentsearch\.gitignore)
- Environment variables still override values from the config file if you set them
- The Prowlarr username and password can live there for future use, but the current API integration uses the API key

## Recommendation

Start with Prowlarr.

- Prowlarr is a better fit when you want one managed indexer layer and a clean API surface.
- Jackett is still usable, but it overlaps with Prowlarr and usually makes the stack more complex if both are always enabled.
- If you eventually need one tracker that behaves better in Jackett, we can add a second provider adapter later.

## What is in this starter

- `app.py`: a single Python server that serves both the web app and JSON API endpoints
- `web/index.html`: a small browser UI for testing searches
- Provider abstraction for:
  - `mock`
  - `prowlarr`
  - `jackett` placeholder

## API endpoints

- `GET /api/health`
- `GET /api/search?q=ubuntu`

Example response shape:

```json
{
  "provider": "mock",
  "configured": false,
  "results": [
    {
      "title": "Ubuntu Example Release 1080p",
      "indexer": "MockIndexer",
      "size": 1610612736,
      "seeders": 84,
      "leechers": 4,
      "publishDate": "2026-03-28T12:00:00Z",
      "link": "magnet:?xt=urn:btih:EXAMPLE1",
      "magnetUrl": "magnet:?xt=urn:btih:EXAMPLE1",
      "protocol": "torrent"
    }
  ]
}
```

## Run locally

```powershell
cd C:\Users\arnyb\Documents\torrentsearch
python app.py
```

Then open:

- Web UI: `http://127.0.0.1:8789/`
- API: `http://127.0.0.1:8790/api/health`

## LAN API access

The project is set up to expose only the API on your LAN:

- Web UI listens on `127.0.0.1:8789`
- API listens on `0.0.0.0:8790`

That means:

- This PC can use the web page locally
- Other devices on your LAN can call the API using this PC's LAN IP

Example:

- `http://192.168.1.25:8790/api/health`
- `http://192.168.1.25:8790/api/search?q=ubuntu`

## Configure Prowlarr

Set these environment variables before running the server:

```powershell
$env:TORRENT_PROVIDER="prowlarr"
$env:PROWLARR_URL="http://127.0.0.1:9696"
$env:PROWLARR_API_KEY="your-api-key"
python app.py
```

## Configure Jackett later

The adapter shape is already there, but the live Jackett call is not implemented yet.

Planned environment variables:

```powershell
$env:TORRENT_PROVIDER="jackett"
$env:JACKETT_URL="http://127.0.0.1:9117"
$env:JACKETT_API_KEY="your-api-key"
python app.py
```

## Notes

- The API intentionally normalizes result fields so the browser app and a future Apple TV client can share one payload shape.
- We should keep anything tracker-specific inside provider adapters instead of leaking that detail into Swift or browser code.
- Only use indexers and content sources you are authorized to access and that are legal in your jurisdiction.
