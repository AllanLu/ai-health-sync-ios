# HealthSync 技能文档

## 项目概述

HealthSync 是一个安全地将 iPhone 健康数据同步到 Mac 的解决方案，通过本地网络进行加密传输。

## 核心技能

### 1. 健康数据同步

- **支持的数据类型**：
  - 活动数据：步数、步行+跑步距离、骑行距离、活动能量、基础能量、运动时间、站立时间、爬楼层数、锻炼
  - 心脏数据：心率、静息心率、步行平均心率、心率变异性、收缩压、舒张压、血氧、呼吸频率、体温、最大摄氧量
  - 睡眠数据：睡眠分析、在床时间、睡眠时间、清醒时间、快速眼动睡眠、核心睡眠、深度睡眠
  - 身体数据：体重、身高、身体质量指数、体脂率、瘦体重

### 2. 安全配对机制

- **固定配对码**：`HealthSync2026`
- **TLS 1.3 加密**：所有通信使用 TLS 1.3 加密
- **证书固定**：使用自签名证书，防止中间人攻击
- **Token 永不过期**：配对后 Token 持续有效

### 3. 网络服务

- **固定端口**：8443
- **Bonjour 服务发现**：通过 `_healthsync._tcp` 服务类型自动发现设备
- **mTLS 双向认证**：客户端和服务器双向验证

### 4. 后台运行

- **静音音频技术**：使用静音音频播放保持后台运行
- **后台任务**：申请后台执行时间
- **后台模式**：支持 `audio` 和 `processing` 后台模式

### 5. 数据导出格式

- **CSV**：分号分隔，适合电子表格导入
- **JSON**：结构化数据，适合程序处理
- **XML**：标准格式，适合系统集成

### 6. 健康洞察仪表板

- **活动概览**：平均步数、活动能量、总距离
- **心脏健康**：平均心率、静息心率、心率变异性、血氧饱和度
- **睡眠分析**：平均睡眠时间、睡眠质量评估
- **趋势图表**：步数趋势、心率趋势
- **健康建议**：基于数据的个性化建议

### 7. 自定义报告生成

- **文本格式**：纯文本报告
- **Markdown 格式**：适合文档和博客
- **HTML 格式**：带样式的网页报告

## CLI 命令

### 发现设备
```bash
healthsync discover [--auto-scan]
```

### 扫描配对
```bash
healthsync scan [--file <路径>] [--debug-pasteboard]
```

### 查看状态
```bash
healthsync status
```

### 获取数据类型
```bash
healthsync types
```

### 获取健康数据
```bash
healthsync fetch --start <开始时间> --end <结束时间> --types <类型列表> [--format csv|json|xml]
```

### 生成健康报告
```bash
healthsync report --start <开始时间> --end <结束时间> [--format text|markdown|html]
```

### 示例
```bash
# 获取步数数据（CSV格式）
healthsync fetch --start 2026-01-01T00:00:00Z --end 2026-12-31T23:59:59Z --types steps

# 获取心率和血氧数据（JSON格式）
healthsync fetch --start 2026-01-01T00:00:00Z --end 2026-12-31T23:59:59Z --types heartRate,bloodOxygen --format json

# 获取睡眠数据（XML格式）
healthsync fetch --start 2026-01-01T00:00:00Z --end 2026-12-31T23:59:59Z --types sleepAnalysis --format xml

# 生成 Markdown 格式报告
healthsync report --start 2026-01-01T00:00:00Z --end 2026-12-31T23:59:59Z --format markdown > report.md

# 生成 HTML 格式报告
healthsync report --start 2026-01-01T00:00:00Z --end 2026-12-31T23:59:59Z --format html > report.html
```

## 使用 curl 直接访问 API

如果 CLI 无法使用，可以直接使用 curl 命令访问 API：

### 前提条件
- iOS 设备和 Mac 在同一局域网
- iOS 应用已启动共享服务
- 已完成配对并获取 Token

### API 端点

#### 1. 配对
```bash
# 配对请求（使用固定配对码 HealthSync2026）
curl -k -X POST https://<iOS设备IP>:8443/api/v1/pair \
  -H "Content-Type: application/json" \
  -d '{"code":"HealthSync2026","clientName":"My Mac"}'
```

响应示例：
```json
{"token":"your-auth-token"}
```

#### 2. 获取服务器状态
```bash
curl -k https://<iOS设备IP>:8443/api/v1/status \
  -H "Authorization: Bearer <your-token>"
```

响应示例：
```json
{
  "status": "ok",
  "version": "1",
  "deviceName": "HealthSync-ABC123",
  "enabledTypes": ["steps", "heartRate", "bloodOxygen"],
  "serverTime": "2026-02-18T06:00:00Z"
}
```

#### 3. 获取已启用的数据类型
```bash
curl -k https://<iOS设备IP>:8443/api/v1/health/types \
  -H "Authorization: Bearer <your-token>"
```

响应示例：
```json
{"enabledTypes": ["steps", "heartRate", "bloodOxygen", "sleepAnalysis"]}
```

#### 4. 获取健康数据
```bash
curl -k -X POST https://<iOS设备IP>:8443/api/v1/health/data \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-token>" \
  -d '{
    "startDate": "2026-01-01T00:00:00Z",
    "endDate": "2026-12-31T23:59:59Z",
    "types": ["steps", "heartRate"]
  }'
```

响应示例：
```json
{
  "status": "ok",
  "samples": [
    {
      "id": "UUID",
      "type": "steps",
      "value": 10000,
      "unit": "count",
      "startDate": "2026-02-18T00:00:00Z",
      "endDate": "2026-02-18T23:59:59Z",
      "sourceName": "iPhone",
      "metadata": null
    }
  ],
  "message": null,
  "hasMore": false,
  "returnedCount": 1
}
```

### 分页查询
```bash
# 获取前1000条记录
curl -k -X POST https://<iOS设备IP>:8443/api/v1/health/data \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-token>" \
  -d '{
    "startDate": "2026-01-01T00:00:00Z",
    "endDate": "2026-12-31T23:59:59Z",
    "types": ["steps"],
    "limit": 1000,
    "offset": 0
  }'
```

### 注意事项
1. `-k` 参数用于跳过 SSL 证书验证（因为使用自签名证书）
2. `<iOS设备IP>` 替换为 iOS 设备的实际 IP 地址
3. `<your-token>` 替换为配对时获取的 Token
4. 固定端口：8443
5. 固定配对码：HealthSync2026

## 技术架构

### iOS 应用
- **语言**：Swift 6
- **最低版本**：iOS 18.2
- **框架**：SwiftUI、HealthKit、Network、CryptoKit、Charts
- **数据持久化**：SwiftData

### Mac CLI
- **语言**：Swift 6
- **最低版本**：macOS 15.0
- **框架**：Foundation、Network、Security、Vision
- **支持架构**：x86_64、arm64、universal

## 安全特性

1. **本地网络限制**：只允许本地网络连接，防止远程攻击
2. **SSRF 防护**：验证所有主机地址，拒绝公共网络地址
3. **速率限制**：每分钟最多 60 次请求
4. **审计日志**：记录所有操作和访问
5. **客户端匿名化**：不存储真实设备名称，使用哈希值代替

## 文件结构

```
.
├── iOS Health Sync App/          # iOS 应用
│   ├── App/                      # 应用入口
│   ├── Core/                     # 核心功能
│   │   ├── Background/           # 后台任务
│   │   ├── Clipboard/            # 剪贴板
│   │   ├── DTO/                  # 数据传输对象
│   │   ├── Models/               # 数据模型
│   │   └── Utilities/            # 工具类
│   ├── Services/                 # 服务层
│   │   ├── HealthKit/            # 健康数据服务
│   │   ├── Network/              # 网络服务
│   │   └── Security/             # 安全服务
│   └── Views/                    # 视图层
│       └── HealthInsightsView.swift  # 健康洞察仪表板
├── macOS/                        # Mac CLI
│   └── HealthSyncCLI/
│       ├── Sources/              # 源代码
│       └── Tests/                # 测试
└── SKILLS.md                     # 本文档
```

## 版本历史

### Version 1.1
- ✅ 血氧支持
- ✅ 自定义数据范围查询
- ✅ XML 导出格式
- ✅ 固定端口 8443
- ✅ 自动开始共享
- ✅ 后台持续运行
- ✅ 中文界面
- ✅ 健康洞察仪表板
- ✅ 自定义报告生成

### Version 1.0
- 初始版本
- 基本健康数据同步
- TLS 加密
- QR 码配对
