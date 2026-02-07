//
//  UpdateService.swift
//  Stori
//
//  The core update service: checks GitHub releases for new versions,
//  manages download lifecycle, and drives the update state machine.
//
//  Architecture:
//  - @Observable for SwiftUI integration (fine-grained updates)
//  - @MainActor for thread safety (UI-driven state machine)
//  - Dependency-injectable URLSession for testability
//  - ETag caching for network efficiency
//  - Exponential backoff on failures
//

import Foundation
import AppKit
import CryptoKit

// MARK: - UpdateService

@Observable
@MainActor
final class UpdateService {
    
    // MARK: - Singleton
    
    static let shared = UpdateService()
    
    // MARK: - Configuration
    
    /// GitHub repository (owner/repo)
    static let githubRepo = "cgcardona/Stori"
    
    /// GitHub API endpoint for the latest release
    static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
    }
    
    /// GitHub API endpoint for all releases (used for "how far behind" computation)
    static var allReleasesURL: URL {
        URL(string: "https://api.github.com/repos/\(githubRepo)/releases?per_page=50")!
    }
    
    /// Periodic check interval (12 hours)
    private static let checkInterval: TimeInterval = 12 * 3600
    
    /// Initial delay after launch before first check (10 seconds)
    private static let launchDelay: TimeInterval = 10
    
    /// Snooze duration in days
    static let snoozeDays = 3
    
    // MARK: - Observable State (drives UI)
    
    /// Current state of the update lifecycle
    private(set) var state: UpdateState = .idle
    
    /// Urgency level for the current available update
    private(set) var urgency: UpdateUrgency = .low
    
    /// Number of releases the user is behind (nil if unknown or up-to-date)
    private(set) var releasesBehindCount: Int?
    
    /// Whether the update banner should be shown (first time for this version)
    private(set) var showBanner: Bool = false
    
    /// Current version of the running app
    let currentVersion: SemanticVersion
    
    /// Current build number
    let currentBuild: String
    
    // MARK: - Internal State (not observable)
    
    @ObservationIgnored
    let store: UpdateStore
    
    @ObservationIgnored
    private let session: URLSession
    
    @ObservationIgnored
    private var periodicCheckTask: Task<Void, Never>?
    
    @ObservationIgnored
    private var downloadTask: Task<Void, Never>?
    
    @ObservationIgnored
    private var activeDownloadHandle: URLSessionDownloadTask?
    
    // MARK: - Initialization
    
    init(
        session: URLSession = .shared,
        store: UpdateStore? = nil,
        currentVersion: SemanticVersion? = nil,
        currentBuild: String? = nil
    ) {
        let resolvedStore = store ?? UpdateStore()
        self.session = session
        self.store = resolvedStore
        
        // Read version from VERSION file (single source of truth), falling back to Info.plist
        let resolvedVersion: String = {
            // Primary: VERSION file in bundle
            if let versionPath = Bundle.main.path(forResource: "VERSION", ofType: nil),
               let content = try? String(contentsOfFile: versionPath, encoding: .utf8) {
                let v = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { return v }
            }
            // Fallback: Info.plist CFBundleShortVersionString
            return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        }()
        self.currentVersion = currentVersion ?? SemanticVersion.parse(resolvedVersion) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
        self.currentBuild = currentBuild ?? (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
    }
    
    nonisolated deinit {
        periodicCheckTask?.cancel()
        downloadTask?.cancel()
    }
    
    // MARK: - Display Properties
    
    /// Full version display string
    var versionDisplayString: String {
        "\(currentVersion.displayString) (\(currentBuild))"
    }
    
    /// Whether an update is available or downloaded
    var hasUpdate: Bool {
        switch state {
        case .updateAvailable, .downloading, .downloaded:
            return true
        default:
            return false
        }
    }
    
    /// The available release, if any
    var availableRelease: ReleaseInfo? {
        switch state {
        case .updateAvailable(let r): return r
        case .downloading: return nil
        case .downloaded(_, let r): return r
        default: return nil
        }
    }
    
    /// Menu item text based on current state
    var menuItemTitle: String {
        switch state {
        case .idle, .upToDate, .aheadOfRelease, .error:
            return "Check for Updates..."
        case .checking:
            return "Checking for Updates..."
        case .updateAvailable(let release):
            return "Update Available (\(release.version.displayString))"
        case .downloading(let progress):
            return "Downloading Update... (\(progress.percent)%)"
        case .downloaded:
            return "Install Update..."
        }
    }
    
    /// Whether the menu item should be enabled
    var menuItemEnabled: Bool {
        switch state {
        case .checking, .downloading:
            return false
        default:
            return true
        }
    }
    
    /// Whether to include beta/prerelease versions
    var includePrereleases: Bool {
        store.betaOptIn
    }
    
    // MARK: - Lifecycle
    
    /// Start background update checks (call from app launch)
    func startBackgroundChecks() {
        periodicCheckTask?.cancel()
        periodicCheckTask = Task { [weak self] in
            guard let self else { return }
            
            // Initial delay after launch
            try? await Task.sleep(for: .seconds(Self.launchDelay))
            guard !Task.isCancelled else { return }
            
            // Check on launch if enough time has passed
            if self.shouldCheckNow {
                await self.performCheck(isManual: false)
            }
            
            // Periodic loop
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.checkInterval))
                guard !Task.isCancelled else { break }
                if self.shouldCheckNow {
                    await self.performCheck(isManual: false)
                }
            }
        }
    }
    
    /// Stop background checks
    func stopBackgroundChecks() {
        periodicCheckTask?.cancel()
        periodicCheckTask = nil
    }
    
    // MARK: - Manual Check
    
    /// Manually trigger an update check (from menu item or UI button).
    /// Clears snooze so results are always shown.
    func checkNow() async {
        store.clearSnooze()
        await performCheck(isManual: true)
    }
    
    // MARK: - Core Check Logic
    
    private var shouldCheckNow: Bool {
        // Respect backoff on failures
        if store.consecutiveFailures > 0 {
            guard let lastCheck = store.lastCheckDate else { return true }
            let elapsed = Date().timeIntervalSince(lastCheck)
            return elapsed >= store.backoffInterval
        }
        
        // Normal interval check
        guard let lastCheck = store.lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) >= Self.checkInterval
    }
    
    /// Perform the actual update check against the GitHub API
    private func performCheck(isManual: Bool) async {
        state = .checking
        
        do {
            let result = try await fetchLatestRelease()
            store.lastCheckDate = Date()
            store.clearFailures()
            
            switch result {
            case .upToDate:
                state = .upToDate
                showBanner = false
                releasesBehindCount = nil
                
            case .aheadOfRelease:
                state = .aheadOfRelease
                showBanner = false
                releasesBehindCount = nil
                
            case .updateAvailable(let release):
                let versionString = release.version.raw
                
                // Record first-seen time
                store.recordFirstSeen(versionString)
                
                // Check if ignored or snoozed (but not for manual checks)
                if !isManual {
                    if store.isVersionIgnored(versionString) {
                        state = .upToDate // Silently hide ignored versions
                        return
                    }
                    if store.isSnoozed(for: versionString) {
                        state = .updateAvailable(release) // Keep state but don't show banner
                        urgency = .from(daysSinceFirstSeen: store.daysSinceFirstSeen(versionString))
                        return
                    }
                }
                
                // Update state
                state = .updateAvailable(release)
                urgency = .from(daysSinceFirstSeen: store.daysSinceFirstSeen(versionString))
                store.lastKnownVersion = versionString
                
                // Show banner only the first time for this version
                if !store.hasBannerBeenShown(for: versionString) || isManual {
                    showBanner = true
                }
                
                // Compute how many releases behind
                await computeReleasesBehind()
                
            case .error(let error):
                if isManual {
                    state = .error(error)
                } else {
                    // For automatic checks, don't disturb the user
                    // Keep previous state if it was meaningful
                    if case .updateAvailable = state { /* keep */ }
                    else { state = .error(error) }
                }
            }
            
        } catch {
            store.recordFailure()
            let updateError = mapError(error)
            if isManual {
                state = .error(updateError)
            }
        }
    }
    
    // MARK: - GitHub API
    
    /// Fetch the latest release from GitHub, using ETag caching
    private func fetchLatestRelease() async throws -> UpdateCheckResult {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Stori/\(currentVersion.raw)", forHTTPHeaderField: "User-Agent")
        
        // Conditional request with ETag
        if let etag = store.cachedETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return .error(.invalidResponse)
        }
        
        switch httpResponse.statusCode {
        case 304:
            // Not Modified - use cached data
            if let cached = store.cachedReleaseJSON {
                return try processReleaseData(cached)
            }
            return .upToDate
            
        case 200:
            // Save ETag and response for future conditional requests
            if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
                store.cachedETag = etag
            }
            store.cachedReleaseJSON = data
            return try processReleaseData(data)
            
        case 403, 429:
            // Rate limited
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            return .error(.rateLimited(retryAfter: retryAfter))
            
        case 404:
            // No releases yet
            return .upToDate
            
        default:
            return .error(.serverError(statusCode: httpResponse.statusCode))
        }
    }
    
    /// Process the raw JSON data from GitHub into an UpdateCheckResult
    private func processReleaseData(_ data: Data) throws -> UpdateCheckResult {
        let ghRelease = try JSONDecoder().decode(GitHubRelease.self, from: data)
        
        // Skip drafts
        if ghRelease.draft {
            return .upToDate
        }
        
        // Skip prereleases unless opted in
        if ghRelease.prerelease && !includePrereleases {
            return .upToDate
        }
        
        // Parse version
        guard let releaseVersion = SemanticVersion.parse(ghRelease.tagName) else {
            return .error(.invalidResponse)
        }
        
        // Compare versions
        if releaseVersion <= currentVersion {
            if releaseVersion == currentVersion {
                return .upToDate
            }
            return .aheadOfRelease
        }
        
        // Find downloadable asset (prefer .dmg, fallback to .zip)
        guard let asset = selectAsset(from: ghRelease.assets) else {
            return .error(.noCompatibleAsset)
        }
        
        guard let downloadURL = URL(string: asset.browserDownloadUrl) else {
            return .error(.invalidResponse)
        }
        
        // Validate download host
        guard Self.isAllowedDownloadHost(downloadURL.host) else {
            return .error(.untrustedSource(downloadURL.host ?? "unknown"))
        }
        
        // Parse published date
        let publishedDate = ghRelease.publishedAt.flatMap { dateString -> Date? in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: dateString) ?? {
                let basic = ISO8601DateFormatter()
                return basic.date(from: dateString)
            }()
        }
        
        let releaseInfo = ReleaseInfo(
            version: releaseVersion,
            tagName: ghRelease.tagName,
            title: ghRelease.name ?? "Stori \(releaseVersion.displayString)",
            releaseNotes: ghRelease.body ?? "",
            publishedAt: publishedDate,
            downloadURL: downloadURL,
            downloadSize: asset.size,
            assetName: asset.name,
            releasePageURL: URL(string: ghRelease.htmlUrl)!,
            isPrerelease: ghRelease.prerelease
        )
        
        return .updateAvailable(releaseInfo)
    }
    
    /// Select the best asset from a release's assets
    private func selectAsset(from assets: [GitHubAsset]) -> GitHubAsset? {
        // Prefer DMG with our naming convention
        let dmgAssets = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        if let preferred = dmgAssets.first(where: { $0.name.lowercased().hasPrefix("stori") }) {
            return preferred
        }
        if let anyDMG = dmgAssets.first {
            return anyDMG
        }
        
        // Fallback to ZIP
        let zipAssets = assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        if let preferred = zipAssets.first(where: { $0.name.lowercased().hasPrefix("stori") }) {
            return preferred
        }
        return zipAssets.first
    }
    
    /// Compute how many releases the user is behind
    private func computeReleasesBehind() async {
        do {
            var request = URLRequest(url: Self.allReleasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Stori/\(currentVersion.raw)", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }
            
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            
            let newerReleases = releases.filter { release in
                guard !release.draft else { return false }
                if release.prerelease && !includePrereleases { return false }
                guard let version = SemanticVersion.parse(release.tagName) else { return false }
                return version > currentVersion
            }
            
            releasesBehindCount = newerReleases.isEmpty ? nil : newerReleases.count
        } catch {
            // Non-critical: don't fail the whole check if we can't count releases
            releasesBehindCount = nil
        }
    }
    
    // MARK: - Download
    
    /// Download the update asset
    func downloadUpdate(_ release: ReleaseInfo) {
        guard Self.isAllowedDownloadHost(release.downloadURL.host) else {
            state = .error(.untrustedSource(release.downloadURL.host ?? "unknown"))
            return
        }
        
        downloadTask?.cancel()
        activeDownloadHandle?.cancel()
        
        downloadTask = Task { [weak self] in
            guard let self else { return }
            
            self.state = .downloading(DownloadProgress(bytesDownloaded: 0, totalBytes: release.downloadSize))
            
            do {
                let fileURL = try await self.performDownload(release: release)
                
                if !Task.isCancelled {
                    self.state = .downloaded(fileURL: fileURL, release: release)
                }
            } catch is CancellationError {
                self.state = .updateAvailable(release)
            } catch {
                let updateError = self.mapError(error)
                if updateError == .downloadCancelled {
                    self.state = .updateAvailable(release)
                } else {
                    self.state = .error(updateError)
                }
            }
        }
    }
    
    /// Cancel an in-progress download
    func cancelDownload() {
        activeDownloadHandle?.cancel()
        downloadTask?.cancel()
        downloadTask = nil
        activeDownloadHandle = nil
        
        // Restore to idle state if we were downloading
        if case .downloading = state {
            state = .idle
        }
    }
    
    /// Perform the actual file download with progress tracking
    private func performDownload(release: ReleaseInfo) async throws -> URL {
        let delegate = UpdateDownloadDelegate { [weak self] bytesWritten, totalBytes in
            Task { @MainActor [weak self] in
                self?.state = .downloading(DownloadProgress(
                    bytesDownloaded: bytesWritten,
                    totalBytes: totalBytes
                ))
            }
        }
        
        let downloadSession = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        
        let request = URLRequest(url: release.downloadURL)
        let (tempURL, response) = try await downloadSession.download(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UpdateError.downloadFailed("Server returned an error")
        }
        
        // Validate minimum file size (at least 1 MB for a real app bundle)
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0
        if fileSize < 1_000_000 {
            throw UpdateError.downloadFailed("Downloaded file is suspiciously small (\(fileSize) bytes)")
        }
        
        // Move to Downloads folder with sanitized name
        let safeVersion = Self.sanitizeVersionForFilename(release.version.raw)
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let ext = release.assetName.hasSuffix(".zip") ? "zip" : "dmg"
        let fileName = "Stori-v\(safeVersion).\(ext)"
        let destination = downloadsDir.appendingPathComponent(fileName)
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        
        return destination
    }
    
    // MARK: - Install
    
    /// Open the downloaded file and guide the user through installation
    func installUpdate(from fileURL: URL) {
        // Reveal in Finder
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
    
    /// Open the downloaded DMG/ZIP and show instructions
    func openDownloadedFile(_ fileURL: URL) {
        NSWorkspace.shared.open(fileURL)
    }
    
    // MARK: - User Actions
    
    /// Snooze notifications for this version
    func snoozeUpdate(_ release: ReleaseInfo) {
        store.snooze(version: release.version.raw, days: Self.snoozeDays)
        showBanner = false
    }
    
    /// Skip (ignore) a specific version permanently
    func skipVersion(_ release: ReleaseInfo) {
        store.ignoreVersion(release.version.raw)
        showBanner = false
        state = .upToDate
    }
    
    /// Dismiss the banner without snoozing or skipping
    func dismissBanner() {
        if case .updateAvailable(let release) = state {
            store.markBannerShown(for: release.version.raw)
        }
        showBanner = false
    }
    
    /// Open the release page in the default browser
    func openReleasePage(_ release: ReleaseInfo) {
        NSWorkspace.shared.open(release.releasePageURL)
    }
    
    /// Toggle beta opt-in
    func setBetaOptIn(_ enabled: Bool) {
        store.betaOptIn = enabled
    }
    
    // MARK: - Security
    
    /// Validate that a download URL points to a trusted GitHub host
    static func isAllowedDownloadHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return h == "github.com"
            || h.hasSuffix(".github.com")
            || h.hasSuffix(".githubusercontent.com")
    }
    
    /// Sanitize a version string for safe use in filenames (prevent path traversal)
    static func sanitizeVersionForFilename(_ version: String) -> String {
        var s = version
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "..", with: ".")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        s = s.components(separatedBy: invalid).joined(separator: "_")
        if s.count > 64 { s = String(s.prefix(64)) }
        return s.isEmpty ? "unknown" : s
    }
    
    // MARK: - Error Mapping
    
    private func mapError(_ error: Error) -> UpdateError {
        if let updateError = error as? UpdateError {
            return updateError
        }
        
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return .networkUnavailable
            case NSURLErrorCancelled:
                return .downloadCancelled
            default:
                return .downloadFailed(error.localizedDescription)
            }
        }
        
        return .downloadFailed(error.localizedDescription)
    }
}

// MARK: - UpdateDownloadDelegate

/// URLSession delegate that reports download progress
private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void
    
    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }
    
    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when
    /// the runtime deinits this object on MainActor/task-local context.
    nonisolated deinit {}
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Handled by the async download(for:) call
    }
}
