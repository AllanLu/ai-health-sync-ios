# HealthSync Skills (Code-Aligned)

> Goal: document the current capabilities from code and enforce that **skills use `curl` only** for data retrieval.

## 1. Scope and Rules

- Data retrieval is supported only through `curl` calls to the iOS HTTPS API.
- CLI commands, report generation, and CSV/XML export are intentionally excluded (not present in current code).
- Pairing route `/api/v1/pair` is not supported by the current server routing.
- This document is aligned with:
  - `iOS Health Sync App/iOS Health Sync App/Services/Network/NetworkServer.swift`
  - `iOS Health Sync App/iOS Health Sync App/Core/DTO/HealthSampleDTO.swift`
  - `iOS Health Sync App/iOS Health Sync App/Core/Models/HealthDataType.swift`

## 2. Network and Security Baseline (From Code)

- Protocol: HTTPS (minimum TLS 1.3)
- Port: fixed `8443`
- Discovery: Bonjour `_healthsync._tcp`
- Request body format: JSON (for POST)
- Date format: ISO 8601 (example: `2026-03-01T00:00:00Z`)
- Current access mode: public (server routes do not validate `Authorization`/token)

> Note: examples use `curl -k` because the app serves a self-signed certificate.

## 3. Skills (curl only)

### Skill 1: Get Server Status

```bash
curl -k "https://<iPhone-IP>:8443/api/v1/status"
```

Sample response:

```json
{
  "status": "ok",
  "version": "1",
  "deviceName": "HealthSync-ABCD",
  "enabledTypes": ["steps", "heartRate"],
  "serverTime": "2026-03-03T01:00:00Z"
}
```

### Skill 2: Get Enabled Data Types

```bash
curl -k "https://<iPhone-IP>:8443/api/v1/health/types"
```

Sample response:

```json
{
  "enabledTypes": ["steps", "heartRate", "bloodOxygen"]
}
```

### Skill 3: Fetch Health Data (with pagination)

```bash
curl -k -X POST "https://<iPhone-IP>:8443/api/v1/health/data" \
  -H "Content-Type: application/json" \
  -d '{
    "startDate": "2026-03-01T00:00:00Z",
    "endDate": "2026-03-03T23:59:59Z",
    "types": ["steps", "heartRate"],
    "limit": 1000,
    "offset": 0
  }'
```

Sample response:

```json
{
  "status": "ok",
  "samples": [
    {
      "id": "A5B4A22C-1A23-4AB0-8B98-25EF4B8F2F1D",
      "type": "steps",
      "value": 8532,
      "unit": "count",
      "startDate": "2026-03-03T00:00:00Z",
      "endDate": "2026-03-03T23:59:59Z",
      "sourceName": "iPhone",
      "metadata": null
    }
  ],
  "message": null,
  "hasMore": false,
  "returnedCount": 1
}
```

## 4. Pagination and Parameter Rules

- `limit` is optional, default `1000`
- `offset` is optional, default `0`
- max `limit` is `10000`
- `limit` must be greater than `0`
- `types` cannot be empty
- `endDate` cannot be earlier than `startDate`
- requested `types` must be enabled on server, otherwise `403`

## 5. Error Semantics

- `400 Bad Request`
  - `Invalid request body`
  - `No data types requested`
  - `Invalid date range`
  - `Limit must be positive`
- `403 Forbidden`
  - `Requested data types are not enabled`
- `404 Not Found`
  - `Unknown route`
- `408 Request Timeout`
  - request incomplete or timed out during parsing
- `413 Payload Too Large`
  - request body too large
- `423 Locked`
  - device is locked (JSON response with `status = "locked"`)

## 6. Supported Health Data Types (`types` values)

### Activity
- `steps`
- `distanceWalkingRunning`
- `distanceCycling`
- `activeEnergyBurned`
- `basalEnergyBurned`
- `exerciseTime`
- `standHours`
- `flightsClimbed`
- `workouts`

### Heart and Vitals
- `heartRate`
- `restingHeartRate`
- `walkingHeartRateAverage`
- `heartRateVariability`
- `bloodPressureSystolic`
- `bloodPressureDiastolic`
- `bloodOxygen`
- `respiratoryRate`
- `bodyTemperature`
- `vo2Max`

### Sleep
- `sleepAnalysis`
- `sleepInBed`
- `sleepAsleep`
- `sleepAwake`
- `sleepREM`
- `sleepCore`
- `sleepDeep`

### Body Metrics
- `weight`
- `height`
- `bodyMassIndex`
- `bodyFatPercentage`
- `leanBodyMass`

## 7. Minimal curl Flow

```bash
# 1) Check server status
curl -k "https://<iPhone-IP>:8443/api/v1/status"

# 2) Check enabled types
curl -k "https://<iPhone-IP>:8443/api/v1/health/types"

# 3) Fetch data
curl -k -X POST "https://<iPhone-IP>:8443/api/v1/health/data" \
  -H "Content-Type: application/json" \
  -d '{"startDate":"2026-03-01T00:00:00Z","endDate":"2026-03-03T23:59:59Z","types":["steps"],"limit":1000,"offset":0}'
```

---

If pairing/token auth or new routes are reintroduced in code, update this document accordingly.

