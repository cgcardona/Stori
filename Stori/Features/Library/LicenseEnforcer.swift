//
//  LicenseEnforcer.swift
//  Stori
//
//  Created by TellUrStori on 12/10/25.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import Observation

/// Enforces license restrictions and tracks usage
@Observable
class LicenseEnforcer {
    static let shared = LicenseEnforcer()
    
    // Play count storage (in-memory for now, would be SQLite in production)
    private(set) var playCounts: [String: Int] = [:]
    
    // UserDefaults keys
    @ObservationIgnored private let playCountsKey = "com.stori.playCounts"
    @ObservationIgnored private let lastPlayDatesKey = "com.stori.lastPlayDates"
    
    private init() {
        loadPlayCounts()
    }
    
    // MARK: - Permission Checks
    
    /// Check if playback is allowed for a license
    func canPlay(license: PurchasedLicense) -> PlaybackPermission {
        // Check expiration first
        if license.isExpired {
            return .denied(reason: "This license has expired")
        }
        
        // Check play count for limited play licenses
        if license.licenseType == .limitedPlay {
            let remaining = getRemainingPlays(for: license)
            if remaining <= 0 {
                return .denied(reason: "No plays remaining")
            }
            if remaining == 1 {
                return .allowedWithWarning(message: "This is your last play!")
            }
            if remaining <= 3 {
                return .allowedWithWarning(message: "Only \(remaining) plays remaining")
            }
        }
        
        // Check expiration warning for time-limited licenses
        if license.licenseType == .timeLimited {
            if let days = license.daysRemaining, days <= 3 {
                return .allowedWithWarning(message: "Expires in \(days) day\(days == 1 ? "" : "s")")
            }
        }
        
        return .allowed
    }
    
    /// Check if download is allowed for a license
    func canDownload(license: PurchasedLicense) -> Bool {
        let accessControl = LicenseAccessControl(licenseType: license.licenseType)
        
        // Check if license type allows download
        guard accessControl.canDownload else { return false }
        
        // Check if license is still valid
        if license.isExpired { return false }
        
        return true
    }
    
    /// Check if resale is allowed for a license
    func canResell(license: PurchasedLicense) -> Bool {
        let accessControl = LicenseAccessControl(licenseType: license.licenseType)
        return accessControl.canResell && !license.isExpired
    }
    
    // MARK: - Play Count Management
    
    /// Get remaining plays for a license
    /// Uses the license's stored remaining plays, minus any additional plays tracked locally
    func getRemainingPlays(for license: PurchasedLicense) -> Int {
        guard license.licenseType == .limitedPlay else {
            return Int.max // Unlimited
        }
        
        // Start with the license's remaining plays (from blockchain/indexer)
        let initialRemaining = license.playsRemaining ?? license.totalPlays ?? 0
        
        // Subtract any plays we've recorded locally since purchase
        let localPlays = playCounts[license.id] ?? 0
        
        return max(0, initialRemaining - localPlays)
    }
    
    /// Record a play for a license
    func recordPlay(for license: PurchasedLicense) {
        guard license.licenseType == .limitedPlay else { return }
        
        let currentCount = playCounts[license.id] ?? 0
        playCounts[license.id] = currentCount + 1
        
        savePlayCounts()
        
        
        // Check if this was the last play
        if getRemainingPlays(for: license) <= 0 {
            // TODO: Notify blockchain to burn token
        }
    }
    
    /// Reset play count for a license (for testing)
    func resetPlayCount(for license: PurchasedLicense) {
        playCounts.removeValue(forKey: license.id)
        savePlayCounts()
    }
    
    // MARK: - Persistence
    
    private func loadPlayCounts() {
        if let data = UserDefaults.standard.dictionary(forKey: playCountsKey) as? [String: Int] {
            playCounts = data
        }
    }
    
    private func savePlayCounts() {
        UserDefaults.standard.set(playCounts, forKey: playCountsKey)
    }
    
    // MARK: - Time Calculations
    
    /// Get formatted time remaining for a time-limited license
    func getTimeRemaining(for license: PurchasedLicense) -> String? {
        guard license.licenseType == .timeLimited,
              let expirationDate = license.expirationDate else {
            return nil
        }
        
        let now = Date()
        guard expirationDate > now else {
            return "Expired"
        }
        
        let components = Calendar.current.dateComponents(
            [.day, .hour, .minute],
            from: now,
            to: expirationDate
        )
        
        if let days = components.day, days > 0 {
            return "\(days) day\(days == 1 ? "" : "s") left"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") left"
        } else if let minutes = components.minute {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") left"
        }
        
        return "Expiring soon"
    }
    
    // MARK: - Blockchain Sync
    
    /// Pending play count updates that need to be synced to blockchain
    private(set) var pendingSync: [String: Int] = [:]
    
    /// Sync play counts to blockchain
    /// Call this periodically or when license is exhausted
    func syncPlayCountsToBlockchain(for license: PurchasedLicense) async throws {
        guard let localPlays = playCounts[license.id], localPlays > 0 else {
            return // Nothing to sync
        }
        
        // Check if already synced
        let syncedPlays = getSyncedPlayCount(for: license)
        let playsToSync = localPlays - syncedPlays
        
        guard playsToSync > 0 else { return }
        
        
        // Mark as pending
        await MainActor.run {
            pendingSync[license.id] = playsToSync
        }
        
        do {
            // Call signing service to sync play count
            try await PlayCountSyncService.shared.syncPlayCount(
                licenseId: license.id,
                instanceId: license.instanceId,
                playsUsed: playsToSync
            )
            
            // Update synced count
            saveSyncedPlayCount(for: license, count: localPlays)
            
            await MainActor.run {
                pendingSync.removeValue(forKey: license.id)
            }
            
            
        } catch {
            await MainActor.run {
                pendingSync.removeValue(forKey: license.id)
            }
            throw error
        }
    }
    
    /// Get the last synced play count for a license
    private func getSyncedPlayCount(for license: PurchasedLicense) -> Int {
        let key = "synced_\(license.id)"
        return UserDefaults.standard.integer(forKey: key)
    }
    
    /// Save the synced play count
    private func saveSyncedPlayCount(for license: PurchasedLicense, count: Int) {
        let key = "synced_\(license.id)"
        UserDefaults.standard.set(count, forKey: key)
    }
    
    /// Get plays remaining for display (used by LibraryCard)
    func getPlaysRemaining(for license: PurchasedLicense) -> Int {
        return getRemainingPlays(for: license)
    }
}

// MARK: - Playback Permission

enum PlaybackPermission: Equatable {
    case allowed
    case allowedWithWarning(message: String)
    case denied(reason: String)
    
    var isAllowed: Bool {
        switch self {
        case .allowed, .allowedWithWarning:
            return true
        case .denied:
            return false
        }
    }
    
    var warningMessage: String? {
        switch self {
        case .allowedWithWarning(let message):
            return message
        case .denied(let reason):
            return reason
        default:
            return nil
        }
    }
}

// MARK: - License Player State

/// Manages the state of the license player with real AVFoundation playback
@Observable
class LicensePlayerState {
    var license: PurchasedLicense?
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 1.0 {
        didSet {
            audioPlayer?.volume = isMuted ? 0 : volume
        }
    }
    var isMuted: Bool = false {
        didSet {
            audioPlayer?.volume = isMuted ? 0 : volume
        }
    }
    var isLoading: Bool = false
    var error: String?
    var showWarning: Bool = false
    var warningMessage: String = ""
    
    @ObservationIgnored private let enforcer = LicenseEnforcer.shared
    @ObservationIgnored private var playbackStarted = false
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?  // For local files
    @ObservationIgnored private var streamPlayer: AVPlayer?      // For IPFS streaming
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var timeObserver: Any?
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    var formattedDuration: String {
        formatTime(duration)
    }
    
    var formattedTimeRemaining: String {
        formatTime(max(0, duration - currentTime))
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    deinit {
        removeStreamTimeObserver()
        stop()
    }
    
    // MARK: - Playback Control
    
    func load(license: PurchasedLicense) {
        // Stop any existing playback
        stop()
        
        self.license = license
        self.isPlaying = false
        self.currentTime = 0
        self.error = nil
        self.playbackStarted = false
        
        // Check permissions
        let permission = enforcer.canPlay(license: license)
        if let warning = permission.warningMessage {
            if permission.isAllowed {
                warningMessage = warning
                showWarning = true
            } else {
                error = warning
            }
        }
        
        // Try to load audio from IPFS URI or local file
        loadAudio(for: license)
    }
    
    private func loadAudio(for license: PurchasedLicense) {
        isLoading = true
        
        // Use ContentDeliveryService for IPFS streaming
        let contentService = ContentDeliveryService.shared
        
        // Check if audio is cached locally first
        if contentService.isAudioCached(for: license) {
            let cachedURL = contentService.getCachedFileURL(for: license)
            loadAudioFromURL(cachedURL)
            return
        }
        
        // Check if we have an audio URI
        guard let audioURI = license.audioURI, !audioURI.isEmpty else {
            isLoading = false
            duration = 225 // 3:45 demo duration
            return
        }
        
        
        // Try to stream from IPFS
        if let streamURL = contentService.getStreamingURL(for: license, enforcer: enforcer) {
            
            // Use AVPlayer for streaming (not AVAudioPlayer which requires local files)
            Task {
                if let player = await contentService.createStreamingPlayer(for: license, enforcer: enforcer) {
                    await MainActor.run {
                        self.streamPlayer = player
                        
                        // Observe duration when ready
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000) // Wait for metadata
                            if let item = player.currentItem {
                                let seconds = CMTimeGetSeconds(item.duration)
                                if !seconds.isNaN && seconds > 0 {
                                    self.duration = seconds
                                } else {
                                    self.duration = 225 // Fallback
                                }
                            }
                        }
                        
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        // Fall back to demo mode
                        isLoading = false
                        duration = 225
                        error = "Could not load audio from IPFS"
                    }
                }
            }
            return
        }
        
        // Check for local sample audio
        if let sampleURL = Bundle.main.url(forResource: "sample", withExtension: "mp3") {
            loadAudioFromURL(sampleURL)
        } else {
            // No audio available - use demo mode
            isLoading = false
            duration = 225 // 3:45 demo duration
        }
    }
    
    private func loadAudioFromURL(_ url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = isMuted ? 0 : volume
            duration = audioPlayer?.duration ?? 225
            isLoading = false
        } catch {
            isLoading = false
            duration = 225 // Fallback
        }
    }
    
    func play() {
        guard let license = license else { return }
        
        let permission = enforcer.canPlay(license: license)
        guard permission.isAllowed else {
            error = permission.warningMessage
            return
        }
        
        // Record play for limited play licenses (only once per session)
        if !playbackStarted && license.licenseType == .limitedPlay {
            enforcer.recordPlay(for: license)
            playbackStarted = true
        }
        
        // Start streaming playback
        if let player = streamPlayer {
            player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 1000))
            player.play()
            player.volume = isMuted ? 0 : volume
            setupStreamTimeObserver()
        }
        // Or local audio playback
        else if let player = audioPlayer {
            player.currentTime = currentTime
            player.play()
        }
        
        isPlaying = true
        startProgressTimer()
    }
    
    func pause() {
        audioPlayer?.pause()
        streamPlayer?.pause()
        isPlaying = false
        stopProgressTimer()
    }
    
    private func setupStreamTimeObserver() {
        guard let player = streamPlayer, timeObserver == nil else { return }
        
        // Add periodic time observer for streaming
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
        }
    }
    
    private func removeStreamTimeObserver() {
        if let observer = timeObserver, let player = streamPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        
        removeStreamTimeObserver()
        streamPlayer?.pause()
        streamPlayer = nil
        
        isPlaying = false
        stopProgressTimer()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to progress: Double) {
        let newTime = duration * progress
        currentTime = newTime
        audioPlayer?.currentTime = newTime
        streamPlayer?.seek(to: CMTime(seconds: newTime, preferredTimescale: 1000))
    }
    
    func skipForward(_ seconds: TimeInterval = 15) {
        let newTime = min(duration, currentTime + seconds)
        currentTime = newTime
        audioPlayer?.currentTime = newTime
        streamPlayer?.seek(to: CMTime(seconds: newTime, preferredTimescale: 1000))
    }
    
    func skipBackward(_ seconds: TimeInterval = 15) {
        let newTime = max(0, currentTime - seconds)
        currentTime = newTime
        audioPlayer?.currentTime = newTime
        streamPlayer?.seek(to: CMTime(seconds: newTime, preferredTimescale: 1000))
    }
    
    // MARK: - Progress Timer
    
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if let player = self.audioPlayer {
                self.currentTime = player.currentTime
                
                // Check if playback finished
                if !player.isPlaying && self.isPlaying && self.currentTime >= self.duration - 0.5 {
                    self.isPlaying = false
                    self.currentTime = 0
                    self.stopProgressTimer()
                }
            } else if self.isPlaying {
                // Demo mode: simulate playback progress
                self.currentTime += 0.1
                if self.currentTime >= self.duration {
                    self.currentTime = 0
                    self.isPlaying = false
                    self.stopProgressTimer()
                }
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

