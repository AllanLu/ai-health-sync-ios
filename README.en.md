# HealthSync iOS (Fork)

> This project is a fork of [espoir1989/ai-health-sync-ios](https://github.com/espoir1989/ai-health-sync-ios). For the full setup guide, API documentation, and Skills usage, please visit the original repository.

HealthSync is an iOS local health-data sharing app. The current version exposes a local HTTPS API and fetches data via `curl`.

## Changes in This Fork

### OLED Screen Blackout Mode

This fork is optimized for using a **spare OLED iPhone** as an always-on HealthKit server:

- **Prevents auto-lock**: The device stays unlocked while the server is running, keeping it always ready to sync
- **Screen blackout**: Tap the "Screen Off" button to display a pure black screen (OLED pixels fully off), hide the status bar and home indicator, and reduce brightness to zero for maximum power savings
- **Tap to restore**: Tap anywhere on the black screen to return to the normal UI
- **Uninterrupted service**: The server continues running during blackout — health data sync is not affected

Ideal for running an old iPhone as a 24/7 HealthKit data server while plugged in, with no need to repeatedly unlock the device.

## Current Capabilities (Code-Aligned)

- Fixed port: `8443`
- Protocol: HTTPS (TLS 1.3)
- Service discovery: Bonjour `_healthsync._tcp`
- API routes:
  - `GET /api/v1/status`
  - `GET /api/v1/health/types`
  - `POST /api/v1/health/data`
- Current access mode: public (no token required)
- `skills` data retrieval mode: `curl` only

## Requirements

- Xcode 16+
- Swift 6
- iOS Deployment Target: `26.2`
- HealthKit read permission on a physical iPhone

## Quick Start

1. Open the project in Xcode:

```text
iOS Health Sync App/iOS Health Sync App.xcodeproj
```

2. Run the app on a physical iPhone.
3. In the app, request HealthKit permission.
4. Start sharing (the app also attempts auto-start on launch).
5. Use `curl` from a device on the same local network.

## API Quick Examples (curl)

### 1) Status

```bash
curl -k "https://<iPhone-IP>:8443/api/v1/status"
```

### 2) Enabled Types

```bash
curl -k "https://<iPhone-IP>:8443/api/v1/health/types"
```

### 3) Fetch Health Data

```bash
curl -k -X POST "https://<iPhone-IP>:8443/api/v1/health/data" \
  -H "Content-Type: application/json" \
  -d '{
    "startDate": "2026-03-01T00:00:00Z",
    "endDate": "2026-03-03T23:59:59Z",
    "types": ["steps"],
    "limit": 1000,
    "offset": 0
  }'
```

## Docs

- English skills: [SKILLS.en.md](SKILLS.en.md)
- 中文 skills: [SKILLS.md](SKILLS.md)
- 中文 README: [README.zh-CN.md](README.zh-CN.md)

