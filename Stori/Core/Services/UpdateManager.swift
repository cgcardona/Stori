//
//  UpdateManager.swift
//  Stori
//
//  Manages auto-updates by checking GitHub releases and prompting users
//  to download and install new versions.
//

import Foundation
import SwiftUI
import CryptoKit

// MARK: - ReleaseInfo

/// Information about a GitHub release
struct ReleaseInfo: Codable, Equatable {
    let version: String
    let releaseDate: String
    let downloadURL: String
    let releaseNotesURL: String?
    let minimumSystemVersion: String?
    let sha256: String?
    let releaseNotes: [String]?
    let criticalUpdate: Bool?
    
    /// Parse version string into comparable components
    var versionComponents: [Int] {
        // Handle formats like "0.1.1-beta.19"
        let cleaned = version
            .replacingOccurrences(of: "v", with: "")
            .replacingOccurrences(of: "-beta.", with: ".")
            .replacingOccurrences(of: "-alpha.", with: ".")
            .replacingOccurrences(of: "-rc.", with: ".")
        
        return cleaned.split(separator: ".").compactMap { Int($0) }
    }
    
    /// Compare versions (returns true if this version is newer than other)
    func isNewerThan(_ other: String) -> Bool {
        let otherComponents = ReleaseInfo(
            version: other,
            releaseDate: "",
            downloadURL: "",
            releaseNotesURL: nil,
            minimumSystemVersion: nil,
            sha256: nil,
            releaseNotes: nil,
            criticalUpdate: nil
        ).versionComponents
        
        let selfComponents = versionComponents
        
        for i in 0..<max(selfComponents.count, otherComponents.count) {
            let selfValue = i < selfComponents.count ? selfComponents[i] : 0
            let otherValue = i < otherComponents.count ? otherComponents[i] : 0
            
            if selfValue > otherValue { return true }
            if selfValue < otherValue { return false }
        }
        
        return false
    }
}

// MARK: - UpdateState

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case downloading(progress: Double)
    case readyToInstall(URL)
    case error(String)
    
    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.checking, .checking): return true
        case (.upToDate, .upToDate): return true
        case (.available(let l), .available(let r)): return l == r
        case (.downloading(let l), .downloading(let r)): return l == r
        case (.readyToInstall(let l), .readyToInstall(let r)): return l == r
        case (.error(let l), .error(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - UpdateManager

/// Manages checking for and downloading updates from GitHub releases
@MainActor
@Observable
final class UpdateManager {
    
    // MARK: - Singleton
    
    static let shared = UpdateManager()
    
    // MARK: - Configuration
    
    /// GitHub repository for releases (format: "owner/repo")
    private let githubRepo = "tellurstori/Stori"
    
    /// URL for the latest release manifest
    private var manifestURL: URL {
        URL(string: "https://raw.githubusercontent.com/\(githubRepo)/main/latest-release.json")!
    }
    
    /// Alternative: Use GitHub API for releases
    private var githubReleasesURL: URL {
        URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
    }
    
    /// How often to check for updates (24 hours)
    private let checkInterval: TimeInterval = 24 * 60 * 60
    
    // MARK: - State
    
    private(set) var state: UpdateState = .idle
    private(set) var lastCheckDate: Date?
    private(set) var availableRelease: ReleaseInfo?
    private(set) var downloadProgress: Double = 0
    
    private var updateCheckTimer: Timer?
    
    // MARK: - Current Version
    
    /// Current app version from bundle
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    /// Current build number
    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
    
    /// Full version string for display
    var versionDisplayString: String {
        "\(currentVersion) (\(currentBuild))"
    }
    
    // MARK: - Computed Properties
    
    /// Whether an update is available
    var updateAvailable: Bool {
        if case .available = state { return true }
        if case .readyToInstall = state { return true }
        return false
    }
    
    /// Version string of available update
    var availableVersion: String? {
        if case .available(let release) = state {
            return release.version
        }
        return availableRelease?.version
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load last check date
        if let date = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date {
            lastCheckDate = date
        }
    }
    
    // MARK: - Check for Updates
    
    /// Check for updates from GitHub
    func checkForUpdates() async {
        state = .checking
        
        do {
            // Try manifest file first
            let release = try await fetchReleaseManifest()
            
            if release.isNewerThan(currentVersion) {
                availableRelease = release
                state = .available(release)
                
                // Post notification for UI
                NotificationCenter.default.post(
                    name: .updateAvailable,
                    object: nil,
                    userInfo: ["release": release]
                )
            } else {
                state = .upToDate
            }
            
            // Update last check time
            lastCheckDate = Date()
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
            
        } catch {
            // Try GitHub API as fallback
            do {
                let release = try await fetchGitHubRelease()
                
                if release.isNewerThan(currentVersion) {
                    availableRelease = release
                    state = .available(release)
                } else {
                    state = .upToDate
                }
                
                lastCheckDate = Date()
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                
            } catch {
                state = .error("Failed to check for updates: \(error.localizedDescription)")
            }
        }
    }
    
    /// Fetch release info from manifest file
    private func fetchReleaseManifest() async throws -> ReleaseInfo {
        let (data, response) = try await URLSession.shared.data(from: manifestURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.networkError
        }
        
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }
    
    /// Fetch release info from GitHub API
    private func fetchGitHubRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: githubReleasesURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.networkError
        }
        
        // Parse GitHub API response
        struct GitHubRelease: Codable {
            let tag_name: String
            let published_at: String
            let html_url: String
            let body: String?
            let assets: [GitHubAsset]
        }
        
        struct GitHubAsset: Codable {
            let name: String
            let browser_download_url: String
        }
        
        let ghRelease = try JSONDecoder().decode(GitHubRelease.self, from: data)
        
        // Find DMG asset
        guard let dmgAsset = ghRelease.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            throw UpdateError.noDMGFound
        }
        
        // Parse release notes from body
        let notes = ghRelease.body?.split(separator: "\n").map { String($0) }
        
        return ReleaseInfo(
            version: ghRelease.tag_name.replacingOccurrences(of: "v", with: ""),
            releaseDate: String(ghRelease.published_at.prefix(10)),
            downloadURL: dmgAsset.browser_download_url,
            releaseNotesURL: ghRelease.html_url,
            minimumSystemVersion: nil,
            sha256: nil,
            releaseNotes: notes,
            criticalUpdate: nil
        )
    }
    
    // MARK: - Download Update
    
    /// Download URL must be from GitHub (prevents redirect to malicious host).
    private static func isAllowedDownloadHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return h == "github.com" || h.hasSuffix(".github.com") || h.hasSuffix(".githubusercontent.com")
    }
    
    /// SECURITY (H-3): Sanitize version string for use in filenames (prevent path traversal).
    private static func sanitizeVersionForFilename(_ version: String) -> String {
        var s = version
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        s = s.components(separatedBy: invalid).joined(separator: "_")
        if s.count > 64 { s = String(s.prefix(64)) }
        return s.isEmpty ? "unknown" : s
    }

    /// Download the update DMG
    func downloadUpdate() async {
        guard let release = availableRelease,
              let url = URL(string: release.downloadURL),
              Self.isAllowedDownloadHost(url.host) else {
            state = .error("No update available to download")
            return
        }

        state = .downloading(progress: 0)
        downloadProgress = 0
        
        do {
            // Create download delegate for progress tracking
            let delegate = DownloadProgressDelegate { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                    self?.state = .downloading(progress: progress)
                }
            }
            
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (tempURL, response) = try await session.download(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw UpdateError.downloadFailed
            }
            
            // Verify checksum if provided
            if let expectedHash = release.sha256 {
                let actualHash = try sha256Hash(of: tempURL)
                guard actualHash.lowercased() == expectedHash.lowercased() else {
                    throw UpdateError.checksumMismatch
                }
            }
            
            // Move to Downloads folder
            // SECURITY (H-3): Sanitize version for filename to prevent path traversal
            let safeVersion = Self.sanitizeVersionForFilename(release.version)
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let dmgName = "Stori-\(safeVersion).dmg"
            let destination = downloadsDir.appendingPathComponent(dmgName)
            
            // Remove existing file if present
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            
            state = .readyToInstall(destination)
            
        } catch {
            state = .error("Download failed: \(error.localizedDescription)")
        }
    }
    
    /// Calculate SHA256 hash of a file
    private func sha256Hash(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Install Update
    
    /// Open the downloaded DMG for installation
    func installUpdate(from dmgURL: URL) {
        // Open the DMG
        NSWorkspace.shared.open(dmgURL)
        
        // Show a dialog with instructions
        let alert = NSAlert()
        alert.messageText = "Update Downloaded"
        alert.informativeText = "The update has been downloaded and opened.\n\n1. Drag Stori to Applications\n2. Replace the existing app\n3. Relaunch Stori"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// Relaunch the app after update
    /// SECURITY: Uses direct Process arguments instead of shell script to prevent injection
    func relaunchApp() {
        let appPath = Bundle.main.bundlePath
        
        // Validate app path exists and is a valid application bundle
        guard FileManager.default.fileExists(atPath: appPath),
              appPath.hasSuffix(".app") else {
            return
        }
        
        // Use direct Process execution instead of shell script
        // This prevents command injection vulnerabilities
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-a", appPath]  // -g: don't bring to front until ready
        
        // Schedule relaunch after a short delay to allow current app to terminate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? process.run()
        }
        
        // Terminate current app
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSApplication.shared.terminate(nil)
        }
    }
    
    // MARK: - Background Checking
    
    /// Start periodic background update checks
    func startBackgroundChecks() {
        // Check if it's time to check again
        if shouldCheckForUpdates {
            Task {
                await checkForUpdates()
            }
        }
        
        // Schedule periodic checks
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForUpdates()
            }
        }
    }
    
    /// Stop background update checks
    func stopBackgroundChecks() {
        updateCheckTimer?.invalidate()
        updateCheckTimer = nil
    }
    
    /// Whether we should check for updates based on last check time
    private var shouldCheckForUpdates: Bool {
        guard let lastCheck = lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) > checkInterval
    }
    
    // MARK: - Skip Version
    
    /// Skip a specific version (don't prompt again)
    func skipVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: "skippedVersion")
        state = .idle
        availableRelease = nil
    }
    
    /// Check if a version has been skipped
    func isVersionSkipped(_ version: String) -> Bool {
        UserDefaults.standard.string(forKey: "skippedVersion") == version
    }
}

// MARK: - UpdateError

enum UpdateError: LocalizedError {
    case networkError
    case noDMGFound
    case downloadFailed
    case checksumMismatch
    case installFailed
    
    var errorDescription: String? {
        switch self {
        case .networkError: return "Network error - please check your connection"
        case .noDMGFound: return "No download available for this update"
        case .downloadFailed: return "Download failed"
        case .checksumMismatch: return "Download verification failed - file may be corrupted"
        case .installFailed: return "Installation failed"
        }
    }
}

// MARK: - DownloadProgressDelegate

private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    
    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Handled by the async download method
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let updateAvailable = Notification.Name("updateAvailable")
    static let updateDownloaded = Notification.Name("updateDownloaded")
}
