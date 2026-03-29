# HealthSync iOS (Fork)

> 本项目基于 [espoir1989/ai-health-sync-ios](https://github.com/espoir1989/ai-health-sync-ios) 二次开发。完整的操作指南、API 文档和 Skills 用法请前往原作者的仓库查看。

HealthSync 是一个 iOS 本地健康数据共享应用，通过本地网络提供 HTTPS API，使用 `curl` 拉取健康数据。

## 本 Fork 的修改

### OLED 熄屏省电模式

本项目针对 **OLED iPhone 备用机** 场景进行了优化：

- **禁止自动锁屏**：服务器运行期间设备不会自动锁屏，始终保持可同步状态
- **熄屏省电**：点击「熄屏省电」按钮后，屏幕显示纯黑画面（OLED 像素完全关闭），同时隐藏状态栏和 Home 横条，屏幕亮度降至最低，最大限度节省电量
- **一键恢复**：点击屏幕任意位置即可恢复正常界面
- **后台不中断**：熄屏期间服务器持续运行，健康数据同步不受影响

适用场景：将一台旧 iPhone 作为 HealthKit 数据服务器 24 小时运行，搭配充电使用，无需反复解锁。

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

