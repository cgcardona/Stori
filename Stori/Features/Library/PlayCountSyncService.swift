//
//  PlayCountSyncService.swift
//  Stori
//
//  Service for syncing play counts to the blockchain.
//  This ensures Limited Play licenses are properly enforced on-chain.
//
//  TODO: Implement direct wallet signing for play count sync
//  Currently stores plays locally until on-chain sync is implemented.
//
//  Created by TellUrStori on 12/10/25.
//

import Foundation

/// Service for syncing play counts to the blockchain
class PlayCountSyncService {
    static let shared = PlayCountSyncService()
    
    private init() {}
    
    // MARK: - Response Types
    
    struct SyncResponse: Codable {
        let success: Bool
        let licenseId: String?
        let playsRecorded: Int?
        let totalPlaysUsed: Int?
        let transactionHash: String?
        let error: String?
    }
    
    // MARK: - Sync Play Count
    
    /// Sync play count to the blockchain
    /// - Parameters:
    ///   - licenseId: The unique license ID
    ///   - instanceId: The blockchain instance ID
    ///   - playsUsed: Number of plays to record
    func syncPlayCount(licenseId: String, instanceId: String, playsUsed: Int) async throws {
        // TODO: Implement direct wallet signing for play count sync
        // For now, just save locally for future sync
        savePendingSync(licenseId: licenseId, instanceId: instanceId, playsUsed: playsUsed)
    }
    
    // MARK: - Pending Sync Queue
    
    private let pendingSyncKey = "com.stori.pendingSyncs"
    
    /// Save a sync operation for retry later
    private func savePendingSync(licenseId: String, instanceId: String, playsUsed: Int) {
        var pending = getPendingSyncs()
        
        // Update or add
        if let index = pending.firstIndex(where: { $0["licenseId"] as? String == licenseId }) {
            // Add to existing
            let existing = (pending[index]["playsUsed"] as? Int) ?? 0
            pending[index]["playsUsed"] = existing + playsUsed
        } else {
            pending.append([
                "licenseId": licenseId,
                "instanceId": instanceId,
                "playsUsed": playsUsed,
                "timestamp": Date().timeIntervalSince1970
            ])
        }
        
        UserDefaults.standard.set(pending, forKey: pendingSyncKey)
    }
    
    /// Get all pending sync operations
    func getPendingSyncs() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: pendingSyncKey) as? [[String: Any]] ?? []
    }
    
    /// Retry all pending sync operations
    func retryPendingSyncs() async {
        let pending = getPendingSyncs()
        guard !pending.isEmpty else { return }
        
        
        var succeeded: [String] = []
        
        for sync in pending {
            guard let licenseId = sync["licenseId"] as? String,
                  let instanceId = sync["instanceId"] as? String,
                  let playsUsed = sync["playsUsed"] as? Int else {
                continue
            }
            
            do {
                try await syncPlayCount(licenseId: licenseId, instanceId: instanceId, playsUsed: playsUsed)
                succeeded.append(licenseId)
            } catch {
            }
        }
        
        // Remove succeeded from pending
        if !succeeded.isEmpty {
            var remaining = pending.filter { sync in
                guard let licenseId = sync["licenseId"] as? String else { return true }
                return !succeeded.contains(licenseId)
            }
            UserDefaults.standard.set(remaining, forKey: pendingSyncKey)
        }
    }
    
    /// Clear all pending syncs
    func clearPendingSyncs() {
        UserDefaults.standard.removeObject(forKey: pendingSyncKey)
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case syncFailed(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid service URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return "Server error: \(message)"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

