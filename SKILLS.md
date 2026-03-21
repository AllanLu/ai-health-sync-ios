# HealthSync Skills（代码对齐版）

> 目标：基于当前代码整理可用能力，并明确 **skills 只支持 `curl` 获取数据**。
> English version: [SKILLS.en.md](SKILLS.en.md)

## 1. 范围与原则

- 仅支持通过 `curl` 调用 iOS 端 HTTPS API 获取数据。
- 不再包含 CLI 命令、报告生成、CSV/XML 导出等说明（当前仓库代码未提供这些能力）。
- 不支持配对接口 `/api/v1/pair`（当前服务端未暴露该路由）。
- 文档以以下代码为准：
  - `iOS Health Sync App/iOS Health Sync App/Services/Network/NetworkServer.swift`
  - `iOS Health Sync App/iOS Health Sync App/Core/DTO/HealthSampleDTO.swift`
  - `iOS Health Sync App/iOS Health Sync App/Core/Models/HealthDataType.swift`

## 2. 网络与安全基线（按代码）

- 协议：HTTPS（TLS 1.3 最低版本）
- 端口：固定 `8443`
- 服务发现：Bonjour `_healthsync._tcp`
- 请求体格式：JSON（POST 接口）
- 日期格式：ISO 8601（例如 `2026-03-01T00:00:00Z`）
- 当前访问模式：**公开访问模式**（服务端路由未校验 `Authorization`/token）

> 注意：由于使用自签名证书，示例中使用 `curl -k` 跳过证书验证。

## 3. Skills（仅 curl）

### Skill 1：获取服务器状态

```bash
curl -k "https://<iOS设备IP>:8443/api/v1/status"
```

返回（示例）：

```json
{
  "status": "ok",
  "version": "1",
  "deviceName": "HealthSync-ABCD",
  "enabledTypes": ["steps", "heartRate"],
  "serverTime": "2026-03-03T01:00:00Z"
}
```

### Skill 2：获取已启用的数据类型

```bash
curl -k "https://<iOS设备IP>:8443/api/v1/health/types"
```

返回（示例）：

```json
{
  "enabledTypes": ["steps", "heartRate", "bloodOxygen"]
}
```

### Skill 3：获取健康数据（支持分页）

```bash
curl -k -X POST "https://<iOS设备IP>:8443/api/v1/health/data" \
  -H "Content-Type: application/json" \
  -d '{
    "startDate": "2026-03-01T00:00:00Z",
    "endDate": "2026-03-03T23:59:59Z",
    "types": ["steps", "heartRate"],
    "limit": 1000,
    "offset": 0
  }'
```

返回（示例）：

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

## 4. 分页与参数规则

- `limit` 可省略，默认 `1000`
- `offset` 可省略，默认 `0`
- `limit` 最大 `10000`
- `limit` 必须大于 `0`
- `types` 不能为空
- `endDate` 不能早于 `startDate`
- 请求的 `types` 必须是服务端已启用类型，否则返回 `403`

## 5. 统一错误语义

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
  - 请求解析超时/不完整
- `413 Payload Too Large`
  - 请求体过大
- `423 Locked`
  - 设备处于锁定状态（返回 JSON，`status = "locked"`）

## 6. 支持的健康数据类型（`types` 可用值）

### 活动
- `steps`
- `distanceWalkingRunning`
- `distanceCycling`
- `activeEnergyBurned`
- `basalEnergyBurned`
- `exerciseTime`
- `standHours`
- `flightsClimbed`
- `workouts`

### 心脏与生命体征
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

### 睡眠
- `sleepAnalysis`
- `sleepInBed`
- `sleepAsleep`
- `sleepAwake`
- `sleepREM`
- `sleepCore`
- `sleepDeep`

### 身体指标
- `weight`
- `height`
- `bodyMassIndex`
- `bodyFatPercentage`
- `leanBodyMass`

## 7. 最小可用 curl 流程

```bash
# 1) 检查服务状态
curl -k "https://<iOS设备IP>:8443/api/v1/status"

# 2) 查看可请求的数据类型
curl -k "https://<iOS设备IP>:8443/api/v1/health/types"

# 3) 拉取数据
curl -k -X POST "https://<iOS设备IP>:8443/api/v1/health/data" \
  -H "Content-Type: application/json" \
  -d '{"startDate":"2026-03-01T00:00:00Z","endDate":"2026-03-03T23:59:59Z","types":["steps"],"limit":1000,"offset":0}'
```

---

如果后续代码重新启用配对/token 或新增路由，请同步更新本文件。
