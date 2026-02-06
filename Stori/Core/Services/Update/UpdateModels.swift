//
//  UpdateModels.swift
//  Stori
//
//  Data models for the update subsystem: GitHub API response types,
//  update state machine, escalation levels, and error types.
//

import Foundation

// MARK: - GitHub API Response Types

/// A GitHub release as returned by the GitHub REST API
struct GitHubRelease: Codable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let publishedAt: String?
    let htmlUrl: String
    let prerelease: Bool
    let draft: Bool
    let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
        case prerelease
        case draft
        case assets
    }
}

/// A downloadable asset attached to a GitHub release
struct GitHubAsset: Codable, Sendable {
    let name: String
    let browserDownloadUrl: String
    let size: Int64
    let contentType: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
        case contentType = "content_type"
    }
}

// MARK: - ReleaseInfo

/// Normalized release information extracted from a GitHub release.
/// This is the app-internal representation used by the update UI.
struct ReleaseInfo: Equatable, Sendable {
    let version: SemanticVersion
    let tagName: String
    let title: String
    let releaseNotes: String       // Raw markdown from GitHub release body
    let publishedAt: Date?
    let downloadURL: URL
    let downloadSize: Int64        // Size in bytes
    let assetName: String          // e.g. "Stori-v0.2.3.dmg"
    let releasePageURL: URL
    let isPrerelease: Bool
    
    /// Human-readable download size (e.g. "45.2 MB")
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
    }
}

// MARK: - UpdateState

/// The state machine for the update lifecycle.
/// Each case is a discrete, testable state.
enum UpdateState: Equatable, Sendable {
    /// No check has been performed yet
    case idle
    
    /// Currently checking GitHub for updates
    case checking
    
    /// App is on the latest version
    case upToDate
    
    /// Current build is newer than the latest release (dev/beta build)
    case aheadOfRelease
    
    /// An update is available
    case updateAvailable(ReleaseInfo)
    
    /// Downloading the update (with progress info)
    case downloading(DownloadProgress)
    
    /// Download complete, ready to install
    case downloaded(fileURL: URL, release: ReleaseInfo)
    
    /// An error occurred (with recovery info)
    case error(UpdateError)
    
    // MARK: - Equatable
    
    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.checking, .checking): return true
        case (.upToDate, .upToDate): return true
        case (.aheadOfRelease, .aheadOfRelease): return true
        case (.updateAvailable(let l), .updateAvailable(let r)): return l == r
        case (.downloading(let l), .downloading(let r)): return l == r
        case (.downloaded(let lURL, let lR), .downloaded(let rURL, let rR)):
            return lURL == rURL && lR == rR
        case (.error(let l), .error(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - DownloadProgress

/// Progress information during download
struct DownloadProgress: Equatable, Sendable {
    let bytesDownloaded: Int64
    let totalBytes: Int64
    
    /// 0.0 to 1.0
    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }
    
    /// Percentage as integer (0–100)
    var percent: Int {
        Int(fraction * 100)
    }
    
    /// Human-readable progress string (e.g. "23.4 MB / 45.2 MB")
    var formattedProgress: String {
        let downloaded = ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(downloaded) / \(total)"
    }
}

// MARK: - UpdateUrgency

/// Escalation level based on days since update was first detected.
/// Controls the color of the update indicator.
enum UpdateUrgency: Int, Comparable, Sendable {
    /// Update just detected (days 0–3): subtle green indicator
    case low = 0
    
    /// Update has been available for a while (days 4–10): yellow indicator
    case medium = 1
    
    /// Update has been available for a long time (days 11+): red indicator
    case high = 2
    
    static func < (lhs: UpdateUrgency, rhs: UpdateUrgency) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    /// Determine urgency from the number of days since first detection
    static func from(daysSinceFirstSeen days: Int) -> UpdateUrgency {
        switch days {
        case 0...3:  return .low
        case 4...10: return .medium
        default:     return .high
        }
    }
}

// MARK: - UpdateError

/// Errors that can occur during the update process
enum UpdateError: LocalizedError, Equatable, Sendable {
    case networkUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case noCompatibleAsset
    case downloadFailed(String)
    case downloadCancelled
    case checksumMismatch
    case invalidResponse
    case untrustedSource(String)
    case fileSystemError(String)
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "No internet connection. We'll check again later."
        case .rateLimited:
            return "GitHub API rate limit reached. We'll try again shortly."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .noCompatibleAsset:
            return "No compatible download found for this release."
        case .downloadFailed(let detail):
            return "Download failed: \(detail)"
        case .downloadCancelled:
            return "Download was cancelled."
        case .checksumMismatch:
            return "Download verification failed. The file may be corrupted."
        case .invalidResponse:
            return "Received an unexpected response from GitHub."
        case .untrustedSource(let host):
            return "Download blocked: untrusted source (\(host))."
        case .fileSystemError(let detail):
            return "File error: \(detail)"
        }
    }
    
    /// Whether this error is transient and should be retried automatically
    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .rateLimited, .serverError:
            return true
        case .downloadFailed, .downloadCancelled, .checksumMismatch,
             .invalidResponse, .noCompatibleAsset, .untrustedSource, .fileSystemError:
            return false
        }
    }
}

// MARK: - UpdateCheckResult

/// The result of an update check, before UI state is applied
enum UpdateCheckResult: Sendable {
    case upToDate
    case aheadOfRelease
    case updateAvailable(ReleaseInfo)
    case error(UpdateError)
}
