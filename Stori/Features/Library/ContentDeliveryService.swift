//
//  ContentDeliveryService.swift
//  Stori
//
//  Handles audio content delivery from IPFS based on license permissions.
//  Manages streaming, downloading, and caching of audio files.
//
//  Created by TellUrStori on 12/10/25.
//

import Foundation
import AVFoundation
import Combine
import Observation

/// Service for delivering audio content based on license permissions
@Observable
class ContentDeliveryService {
    static let shared = ContentDeliveryService()
    
    // MARK: - Observable State (UI-visible)
    
    var isLoading: Bool = false
    var downloadProgress: Double = 0
    var errorMessage: String?
    
    // MARK: - Configuration (internal, not observable)
    
    /// IPFS gateway URLs (fallback chain)
    @ObservationIgnored private let ipfsGateways = [
        "https://ipfs.io/ipfs/",
        "https://cloudflare-ipfs.com/ipfs/",
        "https://gateway.pinata.cloud/ipfs/",
        "https://dweb.link/ipfs/"
    ]
    
    /// Local cache directory for downloaded audio
    private var cacheDirectory: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = paths[0].appendingPathComponent("TellUrStoriAudio")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        return cacheDir
    }
    
    private init() {}
    
    // MARK: - IPFS URL Resolution
    
    /// Convert IPFS URI to HTTP gateway URL
    /// - Parameter ipfsURI: URI in format "ipfs://Qm..." or just the CID
    /// - Returns: HTTP URL for streaming
    func resolveIPFSURL(_ ipfsURI: String, gatewayIndex: Int = 0) -> URL? {
        guard gatewayIndex < ipfsGateways.count else { return nil }
        
        let cid: String
        if ipfsURI.hasPrefix("ipfs://") {
            cid = String(ipfsURI.dropFirst(7))
        } else if ipfsURI.hasPrefix("https://") {
            // Already an HTTP URL
            return URL(string: ipfsURI)
        } else {
            cid = ipfsURI
        }
        
        return URL(string: ipfsGateways[gatewayIndex] + cid)
    }
    
    // MARK: - Streaming
    
    /// Get streaming URL for a license
    /// - Parameters:
    ///   - license: The purchased license
    ///   - enforcer: License enforcer for permission checking
    /// - Returns: URL for streaming, or nil if not allowed
    func getStreamingURL(for license: PurchasedLicense, enforcer: LicenseEnforcer) -> URL? {
        // Check if playback is allowed
        guard enforcer.canPlay(license: license).isAllowed else {
            return nil
        }
        
        // Get the audio URI from the license
        guard let audioURI = license.audioURI, !audioURI.isEmpty else {
            return nil
        }
        
        return resolveIPFSURL(audioURI)
    }
    
    /// Create AVPlayer for streaming with fallback gateways
    /// - Parameters:
    ///   - license: The purchased license
    ///   - enforcer: License enforcer
    /// - Returns: Configured AVPlayer or nil
    func createStreamingPlayer(for license: PurchasedLicense, enforcer: LicenseEnforcer) async -> AVPlayer? {
        guard enforcer.canPlay(license: license).isAllowed else {
            await MainActor.run {
                errorMessage = "Playback not allowed"
            }
            return nil
        }
        
        guard let audioURI = license.audioURI, !audioURI.isEmpty else { return nil }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // Try each gateway until one works
        for (index, _) in ipfsGateways.enumerated() {
            if let url = resolveIPFSURL(audioURI, gatewayIndex: index) {
                
                // Test if URL is reachable
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 5
                
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse,
                       (200...299).contains(httpResponse.statusCode) {
                        
                        let player = AVPlayer(url: url)
                        
                        await MainActor.run {
                            isLoading = false
                        }
                        
                        return player
                    }
                } catch {
                    continue
                }
            }
        }
        
        await MainActor.run {
            isLoading = false
            errorMessage = "Unable to stream audio - all gateways unavailable"
        }
        
        return nil
    }
    
    // MARK: - Download
    
    /// Download audio file for offline access
    /// - Parameters:
    ///   - license: The purchased license
    ///   - enforcer: License enforcer for permission checking
    /// - Returns: Local file URL or nil
    func downloadAudio(for license: PurchasedLicense, enforcer: LicenseEnforcer) async throws -> URL {
        // Check download permission
        guard enforcer.canDownload(license: license) else {
            throw ContentDeliveryError.downloadNotAllowed
        }
        
        guard let audioURI = license.audioURI, !audioURI.isEmpty else {
            throw ContentDeliveryError.invalidAudioURI
        }
        
        // Check if already cached
        let cachedURL = getCachedFileURL(for: license)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }
        
        await MainActor.run {
            isLoading = true
            downloadProgress = 0
            errorMessage = nil
        }
        
        // Try each gateway
        for (index, _) in ipfsGateways.enumerated() {
            if let url = resolveIPFSURL(audioURI, gatewayIndex: index) {
                
                do {
                    let downloadedURL = try await downloadFile(from: url, to: cachedURL)
                    
                    await MainActor.run {
                        isLoading = false
                        downloadProgress = 1.0
                    }
                    
                    return downloadedURL
                } catch {
                    continue
                }
            }
        }
        
        await MainActor.run {
            isLoading = false
            errorMessage = "Download failed - all gateways unavailable"
        }
        
        throw ContentDeliveryError.downloadFailed
    }
    
    /// Get the local cache URL for a license's audio
    func getCachedFileURL(for license: PurchasedLicense) -> URL {
        let filename = "\(license.id)_\(license.instanceId).audio"
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    /// Check if audio is cached locally
    func isAudioCached(for license: PurchasedLicense) -> Bool {
        return FileManager.default.fileExists(atPath: getCachedFileURL(for: license).path)
    }
    
    /// Download file from URL to destination
    private func downloadFile(from sourceURL: URL, to destinationURL: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: sourceURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ContentDeliveryError.serverError
        }
        
        // Move to final destination
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        return destinationURL
    }
    
    // MARK: - Cache Management
    
    /// Clear all cached audio files
    func clearCache() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for file in contents {
            try FileManager.default.removeItem(at: file)
        }
    }
    
    /// Get total cache size in bytes
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        
        if let contents = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in contents {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        
        return totalSize
    }
    
    /// Delete cached audio for a specific license
    func deleteCachedAudio(for license: PurchasedLicense) throws {
        let fileURL = getCachedFileURL(for: license)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

// MARK: - Content Delivery Errors

enum ContentDeliveryError: LocalizedError {
    case downloadNotAllowed
    case downloadFailed
    case streamingNotAllowed
    case serverError
    case invalidAudioURI
    case licenseExpired
    case playLimitReached
    
    var errorDescription: String? {
        switch self {
        case .downloadNotAllowed:
            return "Download is not allowed for this license type"
        case .downloadFailed:
            return "Failed to download audio file"
        case .streamingNotAllowed:
            return "Streaming is not allowed for this license"
        case .serverError:
            return "Server error occurred"
        case .invalidAudioURI:
            return "Invalid audio file location"
        case .licenseExpired:
            return "This license has expired"
        case .playLimitReached:
            return "Play limit reached for this license"
        }
    }
}

