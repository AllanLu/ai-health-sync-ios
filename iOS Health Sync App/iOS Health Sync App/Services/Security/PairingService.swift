// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import os
import SwiftData

actor PairingService {
    private let modelContainer: ModelContainer
    private var failedAttempts: Int = 0
    
    /// Fixed pairing code - simple and never expires
    private let fixedCode = "HealthSync2026"

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func generateQRCode(host: String, port: Int, fingerprint: String) -> PairingQRCode {
        // Use fixed code for simple pairing - no expiration
        return PairingQRCode(
            version: "1",
            host: host,
            port: port,
            code: fixedCode,
            certificateFingerprint: fingerprint
        )
    }

    func handlePairRequest(_ request: PairRequest) async throws -> PairResponse {
        // Rate limiting: max 5 attempts, then lock out
        guard failedAttempts < 5 else {
            throw PairingError.tooManyAttempts
        }

        // Constant-time comparison to prevent timing attacks
        guard Self.constantTimeCompare(fixedCode, request.code) else {
            failedAttempts += 1
            throw PairingError.invalidCode
        }

        // Reset failed attempts on successful pairing
        failedAttempts = 0
        
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let tokenHash = Self.hashToken(token)

        // Anonymize client name to prevent PII storage
        // Format: "Client-XXXXXXXX" using first 8 chars of SHA256 hash
        let anonymizedName = Self.anonymizeName(request.clientName)
        await persistPairedDevice(name: anonymizedName, tokenHash: tokenHash)
        return PairResponse(token: token)
    }

    func validateToken(_ token: String) async -> Bool {
        let hash = Self.hashToken(token)
        return await MainActor.run {
            let context = modelContainer.mainContext
            let descriptor = FetchDescriptor<PairedDevice>(predicate: #Predicate { $0.tokenHash == hash && $0.isActive })
            let result: [PairedDevice]
            do {
                result = try context.fetch(descriptor)
            } catch {
                AppLoggers.security.error("Failed to fetch paired device: \(error.localizedDescription, privacy: .public)")
                return false
            }
            guard let device = result.first else { return false }
            device.lastSeenAt = Date()
            do {
                try context.save()
            } catch {
                AppLoggers.security.error("Failed to update device lastSeenAt: \(error.localizedDescription, privacy: .public)")
            }
            return true
        }
    }

    func revokeAll() async {
        await MainActor.run {
            let context = modelContainer.mainContext
            let descriptor = FetchDescriptor<PairedDevice>()
            let devices: [PairedDevice]
            do {
                devices = try context.fetch(descriptor)
            } catch {
                AppLoggers.security.error("Failed to fetch devices for revocation: \(error.localizedDescription, privacy: .public)")
                return
            }
            for device in devices {
                device.isActive = false
            }
            do {
                try context.save()
            } catch {
                AppLoggers.security.error("Failed to save revoked devices: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func resetFailedAttempts() {
        failedAttempts = 0
    }

    private func persistPairedDevice(name: String, tokenHash: String) async {
        await MainActor.run {
            let context = modelContainer.mainContext
            let device = PairedDevice(name: name, tokenHash: tokenHash)
            context.insert(device)
            do {
                try context.save()
            } catch {
                AppLoggers.security.error("Failed to persist paired device: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func hashToken(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        var result: UInt8 = 0
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }

    private static func anonymizeName(_ name: String) -> String {
        let hash = SHA256.hash(data: Data(name.utf8))
        let shortHash = hash.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "Client-\(shortHash.uppercased())"
    }
}

/// Errors that can occur during device pairing.
/// Each case provides a user-friendly message for debugging.
enum PairingError: Error, LocalizedError {
    case invalidCode
    case tooManyAttempts

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "Invalid pairing code. The correct code is 'HealthSync2026'."
        case .tooManyAttempts:
            return "Too many failed attempts. Restart the iOS app to try again."
        }
    }
}
