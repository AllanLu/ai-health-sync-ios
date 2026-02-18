// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CryptoKit
import Foundation
import Network
import Security
import Vision

struct ClientConfig: Codable {
    let host: String
    let port: Int
    let fingerprint: String
    // Token is stored in Keychain, not in config file
}

struct PairingPayload: Codable {
    let version: String
    let host: String
    let port: Int
    let code: String
    let certificateFingerprint: String
}

enum CLIError: Error {
    case invalidArguments(String)
    case missingConfig
    case requestFailed(String)
}

// MARK: - Version Information

/// CLI version following semantic versioning (SemVer)
let cliVersion = "1.0.0"

/// Build metadata
let cliBuildDate = "2026-01-07"

@main
struct HealthSyncCLI {
    private static let pasteboardTextTypes: [NSPasteboard.PasteboardType] = [
        .string, // public.utf8-plain-text
        NSPasteboard.PasteboardType("public.plain-text"),
        NSPasteboard.PasteboardType("public.utf8-plain-text"),
        NSPasteboard.PasteboardType("public.text"),
        NSPasteboard.PasteboardType("public.json")
    ]

    static func main() async {
        do {
            try await run()
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        var args = CommandLine.arguments
        guard args.count >= 2 else {
            try usage()
            return
        }

        let command = args[1]
        args.removeFirst(2)

        switch command {
        case "version", "--version", "-v":
            printVersion()
        case "discover":
            try await discover(args: args)
        case "scan":
            try await scan(args: args)
        case "pair":
            try await pair(args: args)
        case "status":
            try await status(args: args)
        case "types":
            try await types(args: args)
        case "fetch":
            try await fetch(args: args)
        case "report":
            try await report(args: args)
        default:
            try usage()
        }
    }

    /// Prints version information following CLI best practices
    static func printVersion() {
        print("""
        HealthSyncCLI v\(cliVersion)
        Build: \(cliBuildDate)
        Platform: macOS (\(ProcessInfo.processInfo.operatingSystemVersionString))

        Copyright © 2026 Marcus Neves
        License: Apache-2.0

        Source: https://github.com/mneves75/ai-health-sync-ios
        """)
    }

    static func usage() throws {
        let text = """
        HealthSyncCLI v\(cliVersion)
        通过本地网络安全同步 iPhone 健康数据到 Mac

        版权所有 © 2026 Marcus Neves | 许可证: Apache-2.0

        用法:
          healthsync <命令> [选项]

        命令:
          discover [--auto-scan]           在本地网络发现健康同步设备
          scan [--file <路径>] [--debug-pasteboard]
                                      扫描二维码并配对（从剪贴板或文件）
          pair --host <主机> --port <端口> --code <配对码> --fingerprint <指纹> --name <名称>
          pair --qr <json>                 使用二维码 JSON 字符串配对
          status [--dry-run]               获取服务器状态
          types [--dry-run]                获取已启用的数据类型
          fetch --start <开始时间> --end <结束时间> --types <类型列表> [--format csv|json|xml] [--dry-run]  (默认: csv)
          report --start <开始时间> --end <结束时间> [--format text|markdown|html]  生成健康报告
          version, --version, -v           显示版本信息

        快速开始:
          1. 在 iOS 设备上启动服务器
          2. 复制二维码（点击应用中的复制按钮）
          3. 运行: healthsync scan

        示例:
          healthsync discover --auto-scan
          healthsync scan --file ~/Desktop/qr.png
          healthsync scan --debug-pasteboard
          healthsync fetch --start 2026-01-01T00:00:00Z --end 2026-12-31T23:59:59Z --types steps > steps.csv
          healthsync fetch --start 2026-01-01T00:00:00Z --end 2026-12-31T23:59:59Z --types steps,heartRate --format json | jq
          healthsync report --start 2026-01-01T00:00:00Z --end 2026-12-31T23:59:59Z --format markdown > report.md

        更多信息:
          https://github.com/mneves75/ai-health-sync-ios
        """
        print(text)
    }

    static func discover(args: [String]) async throws {
        let options = try parseOptions(args)
        let autoScan = options["--auto-scan"] == "true"

        print("正在本地网络搜索健康同步设备...")
        let results = await BonjourBrowser.discover(timeout: 5)
        if results.isEmpty {
            print("未找到设备。")
            print("\n故障排除:")
            print("  1. 确保 iOS 应用正在运行且已启用共享")
            print("  2. 两台设备必须在同一 Wi-Fi 网络")
            print("  3. 检查防火墙是否阻止了 mDNS/Bonjour（端口 5353）")
            return
        }
        print("找到 \(results.count) 台设备:\n")
        for result in results {
            print("  \(result.name)")
            print("    主机: \(result.host)")
            print("    端口: \(result.port)")
            print("")
        }

        if autoScan {
            print("自动扫描已启用，正在从剪贴板扫描二维码...")
            print("")
            try await scan(args: args.filter { $0 != "--auto-scan" })
        } else {
            print("使用 'healthsync scan' 命令配合二维码进行配对。")
        }
    }

    static func scan(args: [String]) async throws {
        let options = try parseOptions(args)
        let name = options["--name"] ?? Host.current().localizedName ?? "macOS"
        let debugPasteboard = options["--debug-pasteboard"] == "true"

        // Strategy: Text-first for reliable Universal Clipboard sync.
        // 1. Check clipboard for JSON text (most reliable across devices)
        // 2. Fall back to image scanning (for screenshots)
        // 3. Use file if --file option provided

        let qrPayload: String

        if debugPasteboard {
            await MainActor.run {
                debugPasteboardContents()
            }
        }

        if let filePath = options["--file"] {
            // File-based scanning
            guard let nsImage = NSImage(contentsOfFile: filePath),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CLIError.invalidArguments("无法从以下路径加载图像: \(filePath)")
            }
            print("正在从文件扫描二维码: \(filePath)")
            qrPayload = try detectQRCode(in: cgImage)
            print("二维码已检测!")
        } else if let textPayload = await MainActor.run(body: { try? checkClipboardForJSONPayload() }) {
            // Text-first: Check for JSON pairing payload in clipboard
            // This is the most reliable method via Universal Clipboard
            qrPayload = textPayload
            print("在剪贴板中找到配对载荷（文本）")
        } else {
            // Fall back to image scanning (for screenshots)
            let nsImage: NSImage? = await MainActor.run {
                let pasteboard = NSPasteboard.general

                // 1. Try reading as NSImage object (works for Mac screenshots)
                if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
                    return image
                }

                // 2. Try reading raw PNG data (Universal Clipboard from iOS)
                if let data = pasteboard.data(forType: .png), let image = NSImage(data: data) {
                    return image
                }

                // 3. Try reading raw TIFF data (common macOS clipboard format)
                if let data = pasteboard.data(forType: .tiff), let image = NSImage(data: data) {
                    return image
                }

                return nil
            }

            guard let nsImage,
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CLIError.invalidArguments("""
                    剪贴板中没有配对数据。

                    请尝试以下方法:
                    1. 从 iOS 应用复制（点击复制按钮）- 通过通用剪贴板同步
                    2. 在 Mac 上截取二维码截图（Cmd+Shift+Ctrl+4）
                    3. 使用 --file 选项: healthsync scan --file ~/Desktop/qr.png
                    """)
            }
            print("正在从剪贴板图像扫描二维码...")
            qrPayload = try detectQRCode(in: cgImage)
            print("二维码已检测!")
        }

        // Parse the pairing payload
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: PairingPayload
        do {
            payload = try decoder.decode(PairingPayload.self, from: Data(qrPayload.utf8))
        } catch {
            throw CLIError.invalidArguments("二维码格式无效。期望健康同步配对码。")
        }

        // Validate QR code version for forward compatibility
        guard payload.version == "1" else {
            throw CLIError.invalidArguments("不支持的二维码版本 '\(payload.version)'。请更新 CLI。")
        }

        // Validate host is local network to prevent SSRF attacks
        guard isLocalNetworkHost(payload.host) else {
            throw CLIError.invalidArguments("主机必须在本地网络上（收到: \(payload.host)）")
        }

        print("正在与 \(payload.host):\(payload.port) 配对...")

        // Perform pairing
        let pairRequest = PairRequest(code: payload.code, clientName: name)
        let client = HealthSyncClient(host: payload.host, port: payload.port, token: "", fingerprint: payload.certificateFingerprint)
        let response: PairResponse = try await client.send(path: "/api/v1/pair", method: "POST", body: pairRequest, authorized: false)

        let config = ClientConfig(host: payload.host, port: payload.port, fingerprint: payload.certificateFingerprint)
        try ConfigStore.save(config, token: response.token)
        print("✓ 配对成功!")
        print("\n现在可以运行:")
        print("  healthsync status")
        // Generate dynamic date range example using current date
        let calendar = Calendar.current
        let now = Date()
        let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        let endOfYear = calendar.date(byAdding: DateComponents(year: 1, second: -1), to: startOfYear) ?? now
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startExample = formatter.string(from: startOfYear)
        let endExample = formatter.string(from: endOfYear)
        print("  healthsync fetch --start \(startExample) --end \(endExample) --types steps,heartRate")
    }

    /// Detects and decodes QR codes in an image using Vision framework.
    /// Uses synchronous perform() since VNImageRequestHandler blocks until completion.
    static func detectQRCode(in image: CGImage) throws -> String {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        // Results are available directly on the request after perform() completes
        guard let results = request.results,
              let firstQR = results.first(where: { $0.symbology == .qr }),
              let payload = firstQR.payloadStringValue else {
            throw CLIError.invalidArguments("No QR code found in image. Ensure the QR code is fully visible and in focus.")
        }

        return payload
    }

    /// Checks clipboard for JSON pairing payload (text-first approach for Universal Clipboard).
    ///
    /// Universal Clipboard syncs text more reliably than images between iOS and macOS.
    /// This function checks if the clipboard contains valid JSON that can be parsed
    /// as a PairingPayload. If valid, returns the JSON string for further processing.
    ///
    /// - Returns: The JSON string if clipboard contains valid pairing payload
    /// - Throws: CLIError if clipboard doesn't contain valid pairing JSON
    @MainActor
    static func checkClipboardForJSONPayload() throws -> String {
        let pasteboard = NSPasteboard.general

        guard let text = extractTextPayload(
            stringProvider: { pasteboard.string(forType: $0) },
            dataProvider: { pasteboard.data(forType: $0) }
        ) else {
            throw CLIError.invalidArguments("No text in clipboard")
        }

        // Quick check: must look like JSON object
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else {
            throw CLIError.invalidArguments("Clipboard text is not JSON")
        }

        // Validate it's a valid PairingPayload
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = text.data(using: .utf8),
              let _ = try? decoder.decode(PairingPayload.self, from: data) else {
            throw CLIError.invalidArguments("Clipboard text is not a valid pairing payload")
        }

        return text
    }

    static func extractTextPayload(
        stringProvider: (NSPasteboard.PasteboardType) -> String?,
        dataProvider: (NSPasteboard.PasteboardType) -> Data?
    ) -> String? {
        for type in pasteboardTextTypes {
            if let value = stringProvider(type), !value.isEmpty {
                return value
            }
            if let data = dataProvider(type),
               let value = String(data: data, encoding: .utf8),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Prints pasteboard types and sizes to help debug Universal Clipboard issues.
    /// Only runs when --debug-pasteboard is provided.
    @MainActor
    static func debugPasteboardContents() {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        print("Pasteboard debug:")
        print("  changeCount: \(pasteboard.changeCount)")
        if types.isEmpty {
            print("  types: <none>")
            return
        }
        print("  types:")
        for type in types {
            if let string = pasteboard.string(forType: type) {
                print("    - \(type.rawValue): string (\(string.count) chars)")
            } else if let data = pasteboard.data(forType: type) {
                print("    - \(type.rawValue): data (\(data.count) bytes)")
            } else {
                print("    - \(type.rawValue): <unreadable>")
            }
        }
    }

    static func pair(args: [String]) async throws {
        let options = try parseOptions(args)
        let name = options["--name"] ?? Host.current().localizedName ?? "macOS"
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let host: String
        let port: Int
        let code: String
        let fingerprint: String

        if let qr = options["--qr"] {
            let payload = try decoder.decode(PairingPayload.self, from: Data(qr.utf8))

            // Validate version for forward compatibility
            guard payload.version == "1" else {
                throw CLIError.invalidArguments("不支持的二维码版本 '\(payload.version)'。请更新 CLI。")
            }

            // Validate host is local network to prevent SSRF attacks
            guard isLocalNetworkHost(payload.host) else {
                throw CLIError.invalidArguments("主机必须在本地网络上（收到: \(payload.host)）")
            }

            host = payload.host
            port = payload.port
            code = payload.code
            fingerprint = payload.certificateFingerprint
        } else {
            guard let hostValue = options["--host"],
                  let portValue = options["--port"],
                  let codeValue = options["--code"],
                  let fingerprintValue = options["--fingerprint"] else {
                throw CLIError.invalidArguments("缺少配对参数")
            }

            // Validate host is local network to prevent SSRF attacks
            guard isLocalNetworkHost(hostValue) else {
                throw CLIError.invalidArguments("主机必须在本地网络上（收到: \(hostValue)）")
            }

            // Validate port is a valid number in range
            guard let portNum = Int(portValue), (1...65535).contains(portNum) else {
                throw CLIError.invalidArguments("端口必须是 1 到 65535 之间的数字（收到: \(portValue)）")
            }

            host = hostValue
            port = portNum
            code = codeValue
            fingerprint = fingerprintValue
        }

        let pairRequest = PairRequest(code: code, clientName: name)
        let client = HealthSyncClient(host: host, port: port, token: "", fingerprint: fingerprint)
        let response: PairResponse = try await client.send(path: "/api/v1/pair", method: "POST", body: pairRequest, authorized: false)

        let config = ClientConfig(host: host, port: port, fingerprint: fingerprint)
        try ConfigStore.save(config, token: response.token)
        print("配对成功！令牌已存储到钥匙串。")
    }

    static func status(args: [String]) async throws {
        let options = try parseOptions(args)
        if options["--dry-run"] == "true" {
            print("试运行: 将调用 /api/v1/status")
            return
        }
        let (config, token) = try ConfigStore.load()
        let client = HealthSyncClient(host: config.host, port: config.port, token: token, fingerprint: config.fingerprint)
        let response: StatusResponse = try await client.send(path: "/api/v1/status", method: "GET", body: EmptyBody(), authorized: true)

        // Format status with emoji indicator
        let statusIcon: String
        let statusText: String
        switch response.status.lowercased() {
        case "ok", "ready", "running":
            statusIcon = "✅"
            statusText = "已配对"
        case "error", "failed":
            statusIcon = "❌"
            statusText = "错误"
        default:
            statusIcon = "⚠️"
            statusText = response.status.capitalized
        }

        // Format fingerprint for display (show first 12 chars)
        let shortFingerprint = config.fingerprint.isEmpty ? "未知" : "SHA256:\(config.fingerprint.prefix(12))..."

        // Count data types
        let typeCount = response.enabledTypes.count
        let typesSummary = typeCount == 1 ? "1 种数据类型" : "\(typeCount) 种数据类型"

        print("📡 连接状态: \(statusIcon) \(statusText)")
        print("📱 设备: \(response.deviceName)")
        print("🔒 安全: 是 (mTLS)")
        print("🔐 指纹: \(shortFingerprint)")
        print("📊 已启用: \(typesSummary)")

        // Show version info
        print("📦 版本: \(response.version)")
    }

    static func types(args: [String]) async throws {
        let options = try parseOptions(args)
        if options["--dry-run"] == "true" {
            print("试运行: 将调用 /api/v1/health/types")
            return
        }
        let (config, token) = try ConfigStore.load()
        let client = HealthSyncClient(host: config.host, port: config.port, token: token, fingerprint: config.fingerprint)
        let response: TypesResponse = try await client.send(path: "/api/v1/health/types", method: "GET", body: EmptyBody(), authorized: true)
        print(response.enabledTypes.map { $0.rawValue }.joined(separator: ", "))
    }

    static func fetch(args: [String]) async throws {
        let options = try parseOptions(args)
        guard let startString = options["--start"],
              let endString = options["--end"],
              let typesString = options["--types"] else {
            throw CLIError.invalidArguments("缺少获取参数")
        }
        if options["--dry-run"] == "true" {
            print("试运行: 将调用 /api/v1/health/data 获取 \(typesString)")
            return
        }

        // Parse output format (default: csv for easy spreadsheet import)
        let formatString = options["--format"]?.lowercased() ?? "csv"
        let outputFormat: OutputFormat
        switch formatString {
        case "csv":
            outputFormat = .csv
        case "json":
            outputFormat = .json
        case "xml":
            outputFormat = .xml
        default:
            throw CLIError.invalidArguments("无效格式 '\(formatString)'。请使用 'csv'、'json' 或 'xml'。")
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startDate = formatter.date(from: startString) ?? ISO8601DateFormatter().date(from: startString)
        let endDate = formatter.date(from: endString) ?? ISO8601DateFormatter().date(from: endString)
        guard let startDate, let endDate else {
            throw CLIError.invalidArguments("日期格式无效")
        }

        let types = typesString.split(separator: ",").compactMap { HealthDataType(rawValue: String($0)) }
        if types.isEmpty { throw CLIError.invalidArguments("没有有效的类型") }

        let (config, token) = try ConfigStore.load()
        let client = HealthSyncClient(host: config.host, port: config.port, token: token, fingerprint: config.fingerprint)
        let request = HealthDataRequest(startDate: startDate, endDate: endDate, types: types)
        let response: HealthDataResponse = try await client.send(path: "/api/v1/health/data", method: "POST", body: request, authorized: true)

        switch outputFormat {
        case .json:
            printJSON(response)
        case .csv:
            printCSV(response.samples)
        case .xml:
            printXML(response.samples)
        }
    }

    /// Output format for fetch command
    enum OutputFormat {
        case json
        case csv
        case xml
    }

    /// Prints samples as properly formatted JSON array
    /// Machine-parseable output for piping to jq or other tools
    private static func printJSON(_ response: HealthDataResponse) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        // Create output structure with status and samples
        struct JSONOutput: Encodable {
            let status: String
            let count: Int
            let samples: [HealthSampleDTO]
        }

        let output = JSONOutput(
            status: response.status.rawValue,
            count: response.samples.count,
            samples: response.samples
        )

        if let data = try? encoder.encode(output),
           let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
    }

    /// Prints samples as CSV with semicolon separator
    /// Header: id;type;value;unit;startDate;endDate;sourceName
    private static func printCSV(_ samples: [HealthSampleDTO]) {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        // Print header
        print("id;type;value;unit;startDate;endDate;sourceName")

        // Print each sample as a CSV row
        for sample in samples {
            let startDateStr = dateFormatter.string(from: sample.startDate)
            let endDateStr = dateFormatter.string(from: sample.endDate)
            // Escape semicolons in source name if present
            let escapedSource = sample.sourceName.replacingOccurrences(of: ";", with: "\\;")
            print("\(sample.id);\(sample.type);\(sample.value);\(sample.unit);\(startDateStr);\(endDateStr);\(escapedSource)")
        }
    }

    /// Prints samples as XML
    private static func printXML(_ samples: [HealthSampleDTO]) {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        print("<HealthData>")
        for sample in samples {
            let startDateStr = dateFormatter.string(from: sample.startDate)
            let endDateStr = dateFormatter.string(from: sample.endDate)
            // XML escape source name
            let escapedSource = sample.sourceName
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&apos;")
            print("  <Sample>")
            print("    <ID>\(sample.id)</ID>")
            print("    <Type>\(sample.type)</Type>")
            print("    <Value>\(sample.value)</Value>")
            print("    <Unit>\(sample.unit)</Unit>")
            print("    <StartDate>\(startDateStr)</StartDate>")
            print("    <EndDate>\(endDateStr)</EndDate>")
            print("    <SourceName>\(escapedSource)</SourceName>")
            print("  </Sample>")
        }
        print("</HealthData>")
    }
    
    // MARK: - Report Generation
    
    static func report(args: [String]) async throws {
        let options = try parseOptions(args)
        guard let startString = options["--start"],
              let endString = options["--end"] else {
            throw CLIError.invalidArguments("缺少报告参数")
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startDate = formatter.date(from: startString) ?? ISO8601DateFormatter().date(from: startString)
        let endDate = formatter.date(from: endString) ?? ISO8601DateFormatter().date(from: endString)
        guard let startDate, let endDate else {
            throw CLIError.invalidArguments("日期格式无效")
        }
        
        let (config, token) = try ConfigStore.load()
        let client = HealthSyncClient(host: config.host, port: config.port, token: token, fingerprint: config.fingerprint)
        
        // 获取所有启用的数据类型
        let typesResponse: TypesResponse = try await client.send(path: "/api/v1/health/types", method: "GET", body: EmptyBody(), authorized: true)
        let types = typesResponse.enabledTypes
        
        // 获取数据
        let request = HealthDataRequest(startDate: startDate, endDate: endDate, types: types)
        let response: HealthDataResponse = try await client.send(path: "/api/v1/health/data", method: "POST", body: request, authorized: true)
        
        // 解析报告格式
        let formatString = options["--format"]?.lowercased() ?? "text"
        let reportFormat: ReportFormat
        switch formatString {
        case "text":
            reportFormat = .text
        case "markdown", "md":
            reportFormat = .markdown
        case "html":
            reportFormat = .html
        default:
            throw CLIError.invalidArguments("无效格式 '\(formatString)'。请使用 'text'、'markdown' 或 'html'。")
        }
        
        // 生成报告
        printReport(response.samples, format: reportFormat, startDate: startDate, endDate: endDate)
    }
    
    enum ReportFormat {
        case text
        case markdown
        case html
    }
    
    /// 生成健康报告
    private static func printReport(_ samples: [HealthSampleDTO], format: ReportFormat, startDate: Date, endDate: Date) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        
        // 按类型分组统计
        var stats: [String: TypeStats] = [:]
        for sample in samples {
            if stats[sample.type] == nil {
                stats[sample.type] = TypeStats(type: sample.type, unit: sample.unit)
            }
            stats[sample.type]?.add(value: sample.value)
        }
        
        switch format {
        case .text:
            printTextReport(stats: stats, startDate: startDate, endDate: endDate, dateFormatter: dateFormatter)
        case .markdown:
            printMarkdownReport(stats: stats, startDate: startDate, endDate: endDate, dateFormatter: dateFormatter)
        case .html:
            printHTMLReport(stats: stats, startDate: startDate, endDate: endDate, dateFormatter: dateFormatter)
        }
    }
    
    private static func printTextReport(stats: [String: TypeStats], startDate: Date, endDate: Date, dateFormatter: DateFormatter) {
        print("========================================")
        print("         健康数据报告")
        print("========================================")
        print("")
        print("报告期间: \(dateFormatter.string(from: startDate)) 至 \(dateFormatter.string(from: endDate))")
        print("生成时间: \(dateFormatter.string(from: Date()))")
        print("")
        print("----------------------------------------")
        print("数据摘要")
        print("----------------------------------------")
        
        for (type, stat) in stats.sorted(by: { $0.key < $1.key }) {
            print("")
            print("【\(type)】")
            print("  总计: \(String(format: "%.2f", stat.total)) \(stat.unit)")
            print("  平均: \(String(format: "%.2f", stat.average)) \(stat.unit)")
            print("  最小: \(String(format: "%.2f", stat.min)) \(stat.unit)")
            print("  最大: \(String(format: "%.2f", stat.max)) \(stat.unit)")
            print("  样本数: \(stat.count)")
        }
        
        print("")
        print("========================================")
    }
    
    private static func printMarkdownReport(stats: [String: TypeStats], startDate: Date, endDate: Date, dateFormatter: DateFormatter) {
        print("# 健康数据报告")
        print("")
        print("**报告期间**: \(dateFormatter.string(from: startDate)) 至 \(dateFormatter.string(from: endDate))")
        print("")
        print("**生成时间**: \(dateFormatter.string(from: Date()))")
        print("")
        print("## 数据摘要")
        print("")
        print("| 数据类型 | 总计 | 平均 | 最小 | 最大 | 样本数 | 单位 |")
        print("|----------|------|------|------|------|--------|------|")
        
        for (type, stat) in stats.sorted(by: { $0.key < $1.key }) {
            print("| \(type) | \(String(format: "%.2f", stat.total)) | \(String(format: "%.2f", stat.average)) | \(String(format: "%.2f", stat.min)) | \(String(format: "%.2f", stat.max)) | \(stat.count) | \(stat.unit) |")
        }
        
        print("")
        print("---")
        print("*由 HealthSync 自动生成*")
    }
    
    private static func printHTMLReport(stats: [String: TypeStats], startDate: Date, endDate: Date, dateFormatter: DateFormatter) {
        print("""
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>健康数据报告</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
                h1 { color: #333; border-bottom: 2px solid #007AFF; padding-bottom: 10px; }
                h2 { color: #555; margin-top: 30px; }
                table { width: 100%; border-collapse: collapse; margin-top: 20px; }
                th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
                th { background-color: #007AFF; color: white; }
                tr:nth-child(even) { background-color: #f9f9f9; }
                tr:hover { background-color: #f5f5f5; }
                .meta { color: #666; font-size: 14px; margin-bottom: 20px; }
                .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; color: #999; font-size: 12px; }
            </style>
        </head>
        <body>
            <h1>健康数据报告</h1>
            <div class="meta">
                <p><strong>报告期间:</strong> \(dateFormatter.string(from: startDate)) 至 \(dateFormatter.string(from: endDate))</p>
                <p><strong>生成时间:</strong> \(dateFormatter.string(from: Date()))</p>
            </div>
            <h2>数据摘要</h2>
            <table>
                <tr>
                    <th>数据类型</th>
                    <th>总计</th>
                    <th>平均</th>
                    <th>最小</th>
                    <th>最大</th>
                    <th>样本数</th>
                    <th>单位</th>
                </tr>
        """)
        
        for (type, stat) in stats.sorted(by: { $0.key < $1.key }) {
            print("""
                <tr>
                    <td>\(type)</td>
                    <td>\(String(format: "%.2f", stat.total))</td>
                    <td>\(String(format: "%.2f", stat.average))</td>
                    <td>\(String(format: "%.2f", stat.min))</td>
                    <td>\(String(format: "%.2f", stat.max))</td>
                    <td>\(stat.count)</td>
                    <td>\(stat.unit)</td>
                </tr>
            """)
        }
        
        print("""
            </table>
            <div class="footer">
                <p>由 HealthSync 自动生成</p>
            </div>
        </body>
        </html>
        """)
    }
}

/// 类型统计
private struct TypeStats {
    let type: String
    let unit: String
    var total: Double = 0
    var min: Double = Double.infinity
    var max: Double = -Double.infinity
    var count: Int = 0
    
    var average: Double {
        count > 0 ? total / Double(count) : 0
    }
    
    mutating func add(value: Double) {
        total += value
        min = Swift.min(min, value)
        max = Swift.max(max, value)
        count += 1
    }
}

struct ConfigStore {
    static func configURL() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".healthsync", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        } else {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        return dir.appendingPathComponent("config.json")
    }

    static func save(_ config: ClientConfig, token: String) throws {
        // Save non-sensitive config to file
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        let url = try configURL()
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        // Save token to Keychain
        try KeychainStore.saveToken(token, for: config.host)
    }

    static func load() throws -> (config: ClientConfig, token: String) {
        let url = try configURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.missingConfig
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = try decoder.decode(ClientConfig.self, from: data)
        let token = try KeychainStore.loadToken(for: config.host)
        return (config, token)
    }
}

enum KeychainStore {
    private static let service = "org.mvneves.healthsync.cli"

    static func saveToken(_ token: String, for host: String) throws {
        let account = "token-\(host)"
        guard let tokenData = token.data(using: .utf8) else {
            throw CLIError.requestFailed("Failed to encode token")
        }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CLIError.requestFailed("Failed to save token to Keychain: \(status)")
        }
    }

    static func loadToken(for host: String) throws -> String {
        let account = "token-\(host)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw CLIError.missingConfig
        }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw CLIError.missingConfig
        }
        return token
    }

    static func deleteToken(for host: String) {
        let account = "token-\(host)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct HealthSyncClient {
    let host: String
    let port: Int
    let token: String
    let fingerprint: String

    func send<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body, authorized: Bool) async throws -> Response {
        guard let url = URL(string: "https://\(host):\(port)\(path)") else {
            throw CLIError.invalidArguments("Invalid host or path format")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method != "GET" {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let delegate = PinnedSessionDelegate(expectedFingerprint: fingerprint)
        let sessionConfig: URLSessionConfiguration = {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 30
            c.timeoutIntervalForResource = 60
            return c
        }()
        let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIError.requestFailed("Missing HTTP response")
        }
        let okStatus = (200...299).contains(http.statusCode) || http.statusCode == 423
        guard okStatus else {
            // Include response body for better error diagnosis
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            let errorMessage: String
            if http.statusCode == 400 {
                // Common causes for 400: expired code, invalid code, too many attempts
                errorMessage = """
                    HTTP 400 - Bad Request
                    Server response: \(errorBody)

                    Common causes:
                    • Pairing code has expired - generate a new QR code on iOS app
                    • Too many failed attempts - restart the iOS app
                    • Invalid pairing code format
                    """
            } else {
                errorMessage = "HTTP \(http.statusCode): \(errorBody)"
            }
            throw CLIError.requestFailed(errorMessage)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: data)
    }
}

final class PinnedSessionDelegate: NSObject, URLSessionDelegate {
    private let expectedFingerprint: String

    init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint.lowercased()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let trust = challenge.protectionSpace.serverTrust,
              let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let data = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if fingerprint == expectedFingerprint {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

struct BonjourResult: Sendable {
    let name: String
    let host: String
    let port: Int
}

/// Thread-safe state container for Bonjour discovery.
/// Uses NSLock to safely manage mutable state across callbacks.
private final class BonjourDiscoveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var _collected: [NWEndpoint] = []
    private var _isFinished = false
    private var _continuation: CheckedContinuation<[NWEndpoint], Never>?

    func setContinuation(_ continuation: CheckedContinuation<[NWEndpoint], Never>) {
        lock.lock()
        _continuation = continuation
        lock.unlock()
    }

    func addEndpoint(_ endpoint: NWEndpoint) {
        lock.lock()
        if !_collected.contains(where: { $0 == endpoint }) {
            _collected.append(endpoint)
        }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        guard !_isFinished else {
            lock.unlock()
            return
        }
        _isFinished = true
        let results = _collected
        let cont = _continuation
        lock.unlock()
        cont?.resume(returning: results)
    }
}

/// Thread-safe state container for service resolution.
private final class ServiceResolutionState: @unchecked Sendable {
    private let lock = NSLock()
    private var _hasResumed = false
    private var _continuation: CheckedContinuation<BonjourResult?, Never>?
    private let name: String

    init(name: String) {
        self.name = name
    }

    func setContinuation(_ continuation: CheckedContinuation<BonjourResult?, Never>) {
        lock.lock()
        _continuation = continuation
        lock.unlock()
    }

    func finish(host: String, port: Int) {
        lock.lock()
        guard !_hasResumed else {
            lock.unlock()
            return
        }
        _hasResumed = true
        let cont = _continuation
        lock.unlock()
        cont?.resume(returning: BonjourResult(name: name, host: host, port: port))
    }

    func finishNil() {
        lock.lock()
        guard !_hasResumed else {
            lock.unlock()
            return
        }
        _hasResumed = true
        let cont = _continuation
        lock.unlock()
        cont?.resume(returning: nil)
    }
}

/// Modern Bonjour discovery using Network framework (NWBrowser).
/// Unlike the deprecated NetServiceBrowser, NWBrowser works correctly with Swift Concurrency
/// and doesn't require a RunLoop to deliver callbacks.
enum BonjourBrowser {
    static func discover(timeout: TimeInterval) async -> [BonjourResult] {
        // Create browser for HealthSync service type
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_healthsync._tcp", domain: "local."), using: parameters)

        let state = BonjourDiscoveryState()

        let services = await withCheckedContinuation { (continuation: CheckedContinuation<[NWEndpoint], Never>) in
            state.setContinuation(continuation)

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    state.addEndpoint(result.endpoint)
                }
            }

            browser.stateUpdateHandler = { browserState in
                switch browserState {
                case .failed(let error):
                    AppLoggers.network.error("Browser failed: \(error.localizedDescription)")
                    state.finish()
                case .cancelled:
                    state.finish()
                default:
                    break
                }
            }

            browser.start(queue: .global(qos: .userInitiated))

            // Wait for timeout then return collected services
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                browser.cancel()
                state.finish()
            }
        }

        // Resolve all discovered services in parallel for faster results.
        // Each resolution has a 3-second timeout, so parallel execution
        // significantly improves performance with multiple devices.
        return await withTaskGroup(of: BonjourResult?.self) { group in
            for endpoint in services {
                if case let .service(name, _, _, _) = endpoint {
                    group.addTask {
                        await resolveService(endpoint: endpoint, name: name)
                    }
                }
            }

            var results: [BonjourResult] = []
            for await result in group {
                if let resolved = result {
                    results.append(resolved)
                }
            }
            return results
        }
    }

    /// Resolves a service endpoint to get the actual IP address and port.
    /// Creates a brief connection to trigger resolution, then extracts the address.
    private static func resolveService(endpoint: NWEndpoint, name: String) async -> BonjourResult? {
        let state = ServiceResolutionState(name: name)

        return await withCheckedContinuation { continuation in
            state.setContinuation(continuation)

            let connection = NWConnection(to: endpoint, using: .tcp)

            connection.stateUpdateHandler = { connState in
                switch connState {
                case .ready:
                    // Connection established - extract the resolved address
                    if let path = connection.currentPath,
                       let remoteEndpoint = path.remoteEndpoint,
                       case let .hostPort(host, port) = remoteEndpoint {
                        let hostString = formatHost(host)
                        connection.cancel()
                        state.finish(host: hostString, port: Int(port.rawValue))
                    } else {
                        connection.cancel()
                        state.finishNil()
                    }

                case .failed, .cancelled:
                    state.finishNil()

                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            // Timeout for resolution (3 seconds per service)
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                connection.cancel()
                state.finishNil()
            }
        }
    }

    /// Formats an NWEndpoint.Host to a string suitable for connection.
    private static func formatHost(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let addr):
            return "\(addr)"
        case .ipv6(let addr):
            return "\(addr)"
        case .name(let hostname, _):
            return hostname
        @unknown default:
            return "unknown"
        }
    }
}

// Simple logger for CLI (mirrors iOS pattern)
private enum AppLoggers {
    static let network = CLILogger(category: "network")
}

private struct CLILogger {
    let category: String

    func error(_ message: String) {
        fputs("[\(category)] ERROR: \(message)\n", stderr)
    }

    func info(_ message: String) {
        // Silent in production, could be enabled with --verbose flag
    }
}

struct EmptyBody: Encodable {}

func isLocalNetworkHost(_ host: String) -> Bool {
    // Allow localhost, .local domains, and private IP ranges
    let lowercaseHost = host.lowercased()
    if lowercaseHost == "localhost" || lowercaseHost.hasSuffix(".local") || lowercaseHost.hasSuffix(".local.") {
        return true
    }
    // Check for IPv4 loopback (127.x.x.x)
    if host.starts(with: "127.") {
        return true
    }
    // Check for IPv4 private ranges
    if host.starts(with: "192.168.") || host.starts(with: "10.") {
        return true
    }
    // Check for 172.16.0.0/12 range (172.16.x.x - 172.31.x.x)
    if host.starts(with: "172.") {
        let parts = host.split(separator: ".")
        if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
            return true
        }
    }
    // Allow IPv6 loopback (::1)
    if lowercaseHost == "::1" || lowercaseHost == "[::1]" {
        return true
    }
    // Allow IPv6 link-local (fe80::)
    if lowercaseHost.starts(with: "fe80:") || lowercaseHost.starts(with: "[fe80:") {
        return true
    }
    return false
}

func parseOptions(_ args: [String]) throws -> [String: String] {
    var options: [String: String] = [:]
    var index = 0
    while index < args.count {
        let key = args[index]
        guard key.starts(with: "--") else {
            index += 1
            continue
        }
        let valueIndex = index + 1
        if valueIndex >= args.count || args[valueIndex].starts(with: "--") {
            options[key] = "true"
            index += 1
        } else {
            options[key] = args[valueIndex]
            index += 2
        }
    }
    return options
}

// Shared models mirroring iOS definitions.
struct HealthDataRequest: Codable {
    let startDate: Date
    let endDate: Date
    let types: [HealthDataType]
}

struct HealthDataResponse: Codable {
    let status: HealthDataStatus
    let samples: [HealthSampleDTO]
    let message: String?
}

struct StatusResponse: Codable {
    let status: String
    let version: String
    let deviceName: String
    let enabledTypes: [HealthDataType]
    let serverTime: Date
}

struct TypesResponse: Codable {
    let enabledTypes: [HealthDataType]
}

struct PairRequest: Codable {
    let code: String
    let clientName: String
}

struct PairResponse: Codable {
    let token: String
}

struct HealthSampleDTO: Codable {
    let id: UUID
    let type: String
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date
    let sourceName: String
    let metadata: [String: String]?
}

enum HealthDataStatus: String, Codable {
    case ok
    case noPermission
    case locked
    case error
}

enum HealthDataType: String, CaseIterable, Codable {
    case steps
    case distanceWalkingRunning
    case distanceCycling
    case activeEnergyBurned
    case basalEnergyBurned
    case exerciseTime
    case standHours
    case flightsClimbed
    case workouts
    case heartRate
    case restingHeartRate
    case walkingHeartRateAverage
    case heartRateVariability
    case bloodPressureSystolic
    case bloodPressureDiastolic
    case bloodOxygen
    case respiratoryRate
    case bodyTemperature
    case vo2Max
    case sleepAnalysis
    case sleepInBed
    case sleepAsleep
    case sleepAwake
    case sleepREM
    case sleepCore
    case sleepDeep
    case weight
    case height
    case bodyMassIndex
    case bodyFatPercentage
    case leanBodyMass
}
