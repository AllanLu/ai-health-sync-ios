// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import UIKit

@MainActor
protocol BackgroundTaskManaging: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
    func beginBackgroundTask(withName taskName: String?, expirationHandler handler: (@MainActor @Sendable () -> Void)?) -> UIBackgroundTaskIdentifier
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)
}

extension UIApplication: BackgroundTaskManaging {}

@MainActor
final class BackgroundTaskController {
    private let manager: BackgroundTaskManaging
    private var onExpiration: @MainActor () -> Void
    private var taskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var shouldKeepRunning: Bool = false
    
    /// 静音音频播放器，用于保持应用在后台运行
    private var silentAudioPlayer: AVAudioPlayer?

    init(manager: BackgroundTaskManaging, onExpiration: @escaping @MainActor () -> Void = {}) {
        self.manager = manager
        self.onExpiration = onExpiration
    }

    func setOnExpiration(_ handler: @escaping @MainActor () -> Void) {
        onExpiration = handler
    }

    var isActive: Bool {
        taskIdentifier != .invalid
    }

    @discardableResult
    func beginIfNeeded() -> Bool {
        guard taskIdentifier == .invalid else { return true }
        shouldKeepRunning = true
        
        // 启动后台任务
        let result = beginTask()
        
        // 启动静音音频播放以保持后台运行
        startSilentAudio()
        
        return result
    }
    
    private func beginTask() -> Bool {
        let handler: @MainActor @Sendable () -> Void = { [weak self] in
            self?.handleExpiration()
        }
        let identifier = manager.beginBackgroundTask(withName: "HealthSync Sharing", expirationHandler: handler)
        guard identifier != .invalid else {
            return false
        }
        taskIdentifier = identifier
        return true
    }

    func endIfNeeded() {
        shouldKeepRunning = false
        
        // 停止静音音频
        stopSilentAudio()
        
        guard taskIdentifier != .invalid else { return }
        manager.endBackgroundTask(taskIdentifier)
        taskIdentifier = .invalid
    }

    private func handleExpiration() {
        guard taskIdentifier != .invalid else { return }
        // End the current task
        manager.endBackgroundTask(taskIdentifier)
        taskIdentifier = .invalid
        
        // If we should keep running, start a new task immediately
        if shouldKeepRunning {
            _ = beginTask()
        }
        
        onExpiration()
    }
    
    /// 启动静音音频播放以保持后台运行
    /// 这是iOS上保持后台网络连接的常用技术
    private func startSilentAudio() {
        // 配置音频会话
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 音频会话配置失败，继续使用后台任务
        }
        
        // 创建静音音频数据（0.1秒的静音）
        let data = createSilentWavData()
        
        // 创建音频播放器
        do {
            silentAudioPlayer = try AVAudioPlayer(data: data)
            silentAudioPlayer?.numberOfLoops = -1 // 无限循环
            silentAudioPlayer?.volume = 0.0 // 静音
            silentAudioPlayer?.prepareToPlay()
            silentAudioPlayer?.play()
        } catch {
            // 音频播放器创建失败，继续使用后台任务
        }
    }
    
    /// 创建静音WAV数据
    private func createSilentWavData() -> Data {
        let sampleRate: Double = 44100
        let duration: Double = 0.1
        let samples = Int(sampleRate * duration)
        var data = Data()
        
        // WAV文件头
        let headerSize = 44
        let dataSize = samples * 2 // 16-bit samples
        let fileSize = headerSize + dataSize
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: uint32ToBytes(UInt32(fileSize - 8)))
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: uint32ToBytes(16)) // chunk size
        data.append(contentsOf: uint16ToBytes(1)) // PCM format
        data.append(contentsOf: uint16ToBytes(1)) // mono
        data.append(contentsOf: uint32ToBytes(UInt32(sampleRate))) // sample rate
        data.append(contentsOf: uint32ToBytes(UInt32(sampleRate * 2))) // byte rate
        data.append(contentsOf: uint16ToBytes(2)) // block align
        data.append(contentsOf: uint16ToBytes(16)) // bits per sample
        
        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: uint32ToBytes(UInt32(dataSize)))
        
        // 静音数据（全零）
        for _ in 0..<samples {
            data.append(contentsOf: [0, 0])
        }
        
        return data
    }
    
    /// 停止静音音频播放
    private func stopSilentAudio() {
        silentAudioPlayer?.stop()
        silentAudioPlayer = nil
        
        // 停用音频会话
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    // 辅助函数：将UInt32转换为小端字节
    private func uint32ToBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }
    
    // 辅助函数：将UInt16转换为小端字节
    private func uint16ToBytes(_ value: UInt16) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF)
        ]
    }
}
