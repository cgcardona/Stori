# Backend Prompt: Asset Endpoints – UUID-Only Auth (No JWT)

Use this prompt with your backend Python agent to implement the required changes for Stori asset downloads.

---

## 1. Goal

**Asset endpoints** (drum kits, soundfonts, and their download URLs) must **stop requiring JWT** and instead accept **only a device/app UUID** sent in a request header. This matches the macOS app: it no longer sends `Authorization: Bearer <token>` for assets and never touches the user's Keychain for asset downloads. Composer and user endpoints keep JWT as before.

---

## 2. Affected Routes (assets only)

All of these should require **only** the device UUID (no JWT):

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/assets/drum-kits` | List available drum kits |
| GET | `/api/v1/assets/soundfonts` | List available soundfonts |
| GET | `/api/v1/assets/drum-kits/{kit_id}/download-url` | Presigned URL for a drum kit zip |
| GET | `/api/v1/assets/soundfonts/{soundfont_id}/download-url` | Presigned URL for a soundfont file |
| GET | `/api/v1/assets/bundle/download-url` | Presigned URL for full asset bundle |

- **Health** stays unauthenticated: `GET /api/v1/health` — no auth.
- **All other API routes** (composer, conversations, users, validate-token, etc.) **keep JWT** (`Authorization: Bearer <token>`). Do not change those.

---

## 3. Request Header: Device UUID

- **Header name:** `X-Device-ID`
- **Value:** A UUID string (e.g. `550e8400-e29b-41d4-a716-446655440000`). Same format the app already sends as `user_id` in `POST /api/v1/users/register` for composer registration.
- The macOS app generates this UUID once per install, stores it in UserDefaults, and sends it on every asset request. No Keychain involved.

**Validation:**

- Require that `X-Device-ID` is present and non-empty for the asset routes above.
- Optionally validate that the value looks like a UUID (e.g. regex or UUID parse). Reject or return 400 if missing or invalid.
- Do **not** require `Authorization` or any JWT for these routes. If the backend currently checks JWT (e.g. `require_valid_token`) on asset routes, remove that for assets and replace with a check for `X-Device-ID` only.

---

## 4. Abuse Prevention (no JWT)

Since assets are no longer gated by JWT, protect the endpoints by:

- **Rate limiting by `X-Device-ID`** (e.g. requests per minute per device ID).
- **Rate limiting by IP** (e.g. requests per minute per IP) as a second layer.
- Optionally **log or track** device IDs (e.g. first-seen time, request count) for abuse analysis; no need to “register” devices in a DB unless you want to.

Reject with **429 Too Many Requests** (or your standard rate-limit response) when limits are exceeded. Do not require JWT for assets.

---

## 5. Error Responses

- **Missing or invalid `X-Device-ID`:** Return **400 Bad Request** (or **401** if you prefer) with a clear body (e.g. `{"detail": "X-Device-ID header required"}`). The app will show a generic “Could not load from server” style message.
- **Rate limit exceeded:** **429** with appropriate body/headers.
- **404 / 503 / 5xx:** Keep current behavior for “kit not found”, “service unavailable”, etc.

---

## 6. Presigned URLs (unchanged)

- Download-URL endpoints should continue to return JSON with `url` (presigned S3 URL) and `expires_at` (ISO 8601).
- Expiry (e.g. 30 minutes) and the way presigned URLs are generated do not need to change. Only the **auth** at the API layer changes: require `X-Device-ID` instead of JWT for issuing those URLs.

---

## 7. Summary Checklist for Backend

- [ ] For **asset routes only** (list drum-kits, list soundfonts, all three download-url endpoints): require **`X-Device-ID`** header (UUID); do **not** require JWT.
- [ ] Remove JWT/`require_valid_token` (or equivalent) from those asset routes; replace with validation of `X-Device-ID`.
- [ ] Add rate limiting by `X-Device-ID` (and optionally by IP) for asset endpoints.
- [ ] Return 400 (or 401) when `X-Device-ID` is missing or invalid; 429 when rate limit exceeded.
- [ ] Leave **health** unauthenticated.
- [ ] Leave **all non-asset routes** (composer, conversations, users, validate-token, etc.) **unchanged** — they continue to require JWT only.

---

## 8. Reference: App Behavior

- The Stori macOS app sends **`X-Device-ID: <uuid>`** on every request to the asset endpoints above. The same UUID is used for `POST /api/v1/users/register` (composer) as `user_id`.
- The app does **not** send `Authorization: Bearer` for asset list or download-url requests. It only uses JWT for composer and user-related endpoints.

Implement the above so that asset downloads work with UUID-only auth and remain protected by rate limiting.
