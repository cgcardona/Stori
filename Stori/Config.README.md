# Configuration Setup

## For Official DMG Users (Recommended)

**Download the official DMG** from [releases](https://github.com/tellurstori/Stori/releases) to use TellUrStori's backend for drum kit downloads and other cloud features.

The official DMG is pre-configured and requires no setup.

---

## For Building from Source

If you're building from source, you have two options:

### Option 1: Use TellUrStori Backend (Requires Permission)

Contact the TellUrStori team for API access, then:

1. Copy `Config.plist.example` to `Config.plist`
2. Update `ApiBaseURL` to the provided URL
3. Build the app

### Option 2: Use Your Own Backend

If you want to host your own backend for drum kits and content:

1. Copy `Config.plist.example` to `Config.plist`
2. Set `ApiBaseURL` to your backend URL
3. Implement backend endpoints (see API docs below)
4. Build the app

**Or** set an environment variable:
```bash
export STORI_API_URL="https://your-backend.com"
```

---

## Without Backend Configuration

If you build without a backend (no `Config.plist` and no environment variable):

- ✅ DAW features work normally
- ✅ Built-in drum samples work
- ❌ Remote drum kit downloads disabled
- ❌ Cloud content delivery disabled

---

## Required Backend Endpoints

If implementing your own backend, you need:

- `GET /api/drum-kits` - List available drum kits
- `GET /api/drum-kits/:id/download` - Download drum kit assets
- Authentication (optional but recommended)

See backend API documentation for details.

---

## Files

- **`Config.plist`** - Your actual configuration (gitignored, not in repo). Put the real API base URL here for staging/production; never commit it.
- **`Config.plist.example`** - Template with placeholder URL only. Copy to `Config.plist` and set `ApiBaseURL` to the URL you are given or use for local dev.
- **`AppConfig.swift`** - Loads at runtime: `STORI_API_URL` env → `Config.plist` → fallback example URL in DEBUG only.

---

## Security Notes

- `Config.plist` is **gitignored** so real backend URLs and secrets are never committed.
- Official DMGs are built with the real URL injected via `Config.plist` or build-time plist; the repo contains no hardcoded production or staging URLs.
- Custom backends should use HTTPS in production.
