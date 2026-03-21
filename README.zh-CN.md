# HealthSync iOS

HealthSync 是一个 iOS 本地健康数据共享应用。当前版本通过本地网络提供 HTTPS API，使用 `curl` 拉取健康数据。

## 当前能力（代码对齐）

- 固定端口：`8443`
- 协议：HTTPS（TLS 1.3）
- 服务发现：Bonjour `_healthsync._tcp`
- API 路由：
  - `GET /api/v1/status`
  - `GET /api/v1/health/types`
  - `POST /api/v1/health/data`
- 当前访问模式：公开访问（不要求 token）
- `skills` 数据获取方式：仅支持 `curl`

## 环境要求

- Xcode 16+
- Swift 6
- iOS Deployment Target: `26.2`
- 需要在真机上授予 HealthKit 读取权限

## 快速开始

1. 用 Xcode 打开项目：

```text
iOS Health Sync App/iOS Health Sync App.xcodeproj
```

2. 连接 iPhone 真机并运行 App。
3. 在 App 内点击“请求健康数据访问权限”并允许访问。
4. 启动共享服务（应用启动后会自动尝试启动）。
5. 在同一局域网设备上使用 `curl` 调用 API。

## API 快速示例（curl）

### 1) 状态

```bash
curl -k "https://<iOS设备IP>:8443/api/v1/status"
```

### 2) 已启用类型

```bash
curl -k "https://<iOS设备IP>:8443/api/v1/health/types"
```

### 3) 拉取健康数据

```bash
curl -k -X POST "https://<iOS设备IP>:8443/api/v1/health/data" \
  -H "Content-Type: application/json" \
  -d '{
    "startDate": "2026-03-01T00:00:00Z",
    "endDate": "2026-03-03T23:59:59Z",
    "types": ["steps"],
    "limit": 1000,
    "offset": 0
  }'
```

## 文档导航

- 中文 skills: [SKILLS.md](SKILLS.md)
- English skills: [SKILLS.en.md](SKILLS.en.md)
- English README: [README.en.md](README.en.md)

