# Project Context

- This repository contains a Swift/Xcode Apple TV app in `BiffDownload/`.
- The app target is `BiffDownload` in `BiffDownload/BiffDownload.xcodeproj`.
- The app is a tvOS client that talks to a related LAN server.
- The server-side reference code is in `server/`, but it runs on another machine and is kept here for backup/reference.
- App config is loaded from bundled JSON files in `BiffDownload/BiffDownload/`.
- `apple-tv.config.local.json` is for local development and should stay out of Git.
- The app currently tries to reach server `DESKTOP-SB0Q7M3` by hostname first, then falls back to the configured LAN IP.
- Do not run Xcode or build verification checks unless the user explicitly asks for them.
