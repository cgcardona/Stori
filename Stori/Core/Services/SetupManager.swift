//
//  SetupManager.swift
//  Stori
//
//  Manages first-run setup and SoundFont download for MIDI playback.
//  AI model downloading has been removed - AI is now cloud-based.
//

import Foundation
import SwiftUI
import Combine

// MARK: - SetupComponent

/// Represents a downloadable component (SoundFont for MIDI instruments)
enum SetupComponent: String, CaseIterable, Identifiable, Codable {
    case soundFont = "soundFont"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .soundFont: return "MIDI Instruments"
        }
    }
    
    var description: String {
        switch self {
        case .soundFont: return "FluidR3 GM SoundFont for 128 MIDI instruments"
        }
    }
    
    var icon: String {
        switch self {
        case .soundFont: return "pianokeys"
        }
    }
    
    /// Estimated download size in bytes
    var estimatedSize: Int64 {
        switch self {
        case .soundFont: return 140_000_000   // 140 MB
        }
    }
    
    /// Human-readable size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file)
    }
    
    /// Whether this component is required for basic functionality
    var isRequired: Bool {
        self == .soundFont
    }
    
    /// Direct download URL (for SoundFont)
    var downloadURL: URL? {
        switch self {
        case .soundFont:
            // FluidR3_GM SoundFont - reliable mirror
            return URL(string: "https://keymusician01.s3.amazonaws.com/FluidR3_GM.sf2")
        }
    }
    
    /// Fallback URLs for SoundFont
    static var soundFontFallbackURLs: [URL] {
        [
            URL(string: "https://keymusician01.s3.amazonaws.com/FluidR3_GM.sf2")!,
            URL(string: "https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf2")!
        ]
    }
}

// MARK: - ComponentStatus

/// Tracks the download/installation status of a component
struct ComponentStatus: Identifiable {
    let component: SetupComponent
    var isInstalled: Bool
    var isDownloading: Bool
    var progress: Double // 0.0 to 1.0
    var bytesDownloaded: Int64
    var downloadSpeed: Double // bytes per second
    var error: Error?
    
    var id: String { component.id }
    
    var estimatedTimeRemaining: TimeInterval? {
        guard isDownloading, downloadSpeed > 0 else { return nil }
        let remaining = Double(component.estimatedSize) - Double(bytesDownloaded)
        return remaining / downloadSpeed
    }
    
    var formattedProgress: String {
        let downloaded = ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
        let total = component.formattedSize
        return "\(downloaded) / \(total)"
    }
    
    var formattedSpeed: String {
        let speed = ByteCountFormatter.string(fromByteCount: Int64(downloadSpeed), countStyle: .file)
        return "\(speed)/s"
    }
    
    var formattedETA: String {
        guard let eta = estimatedTimeRemaining else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: eta) ?? ""
    }
}

// MARK: - SetupState

enum SetupState: Equatable {
    case notStarted
    case checking
    case ready(missingComponents: [SetupComponent])
    case downloading
    case completed
    case error(String)
    
    static func == (lhs: SetupState, rhs: SetupState) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted): return true
        case (.checking, .checking): return true
        case (.ready(let l), .ready(let r)): return l == r
        case (.downloading, .downloading): return true
        case (.completed, .completed): return true
        case (.error(let l), .error(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - SetupManager

/// Manages first-run setup and SoundFont download
@MainActor
@Observable
final class SetupManager {
    
    // MARK: - Singleton
    
    static let shared = SetupManager()
    
    // MARK: - State
    
    private(set) var state: SetupState = .notStarted
    private(set) var components: [ComponentStatus] = []
    private(set) var overallProgress: Double = 0
    private(set) var currentDownload: SetupComponent?
    
    // MARK: - Settings
    
    /// Whether setup has been completed at least once
    var hasCompletedSetup: Bool {
        get { UserDefaults.standard.bool(forKey: "setupCompleted") }
        set { UserDefaults.standard.set(newValue, forKey: "setupCompleted") }
    }
    
    /// Whether to show the setup wizard on launch
    var shouldShowSetupWizard: Bool {
        !hasCompletedSetup || hasMissingRequiredComponents
    }
    
    /// Whether any required components are missing
    var hasMissingRequiredComponents: Bool {
        components.contains { $0.component.isRequired && !$0.isInstalled }
    }
    
    // MARK: - Directories
    
    private var applicationSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stori", isDirectory: true)
    }
    
    var soundFontsDirectory: URL {
        applicationSupportDir.appendingPathComponent("SoundFonts", isDirectory: true)
    }
    
    // MARK: - Download Task Management
    
    private var downloadTasks: [SetupComponent: URLSessionDownloadTask] = [:]
    
    // MARK: - Initialization
    
    private init() {
        createDirectories()
        initializeComponents()
    }
    
    private func createDirectories() {
        let dirs = [applicationSupportDir, soundFontsDirectory]
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    private func initializeComponents() {
        components = SetupComponent.allCases.map { component in
            ComponentStatus(
                component: component,
                isInstalled: checkIfInstalled(component),
                isDownloading: false,
                progress: 0,
                bytesDownloaded: 0,
                downloadSpeed: 0,
                error: nil
            )
        }
    }
    
    // MARK: - Installation Check
    
    private func checkIfInstalled(_ component: SetupComponent) -> Bool {
        let path = installPath(for: component)
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    /// Returns the installation path for a component
    func installPath(for component: SetupComponent) -> URL {
        switch component {
        case .soundFont:
            return soundFontsDirectory.appendingPathComponent("FluidR3_GM.sf2")
        }
    }
    
    // MARK: - Disk Space
    
    /// Check if there's enough disk space for the selected components
    func checkDiskSpace(for selectedComponents: Set<SetupComponent>) throws -> Bool {
        let requiredSpace = selectedComponents.reduce(Int64(0)) { $0 + $1.estimatedSize }
        let buffer: Int64 = 500_000_000 // 500 MB buffer
        let totalRequired = requiredSpace + buffer
        
        let values = try applicationSupportDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else {
            return true // Assume OK if we can't check
        }
        
        return available > totalRequired
    }
    
    /// Get available disk space as formatted string
    var availableDiskSpace: String {
        do {
            let values = try applicationSupportDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage {
                return ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            }
        } catch {
            // Ignore
        }
        return "Unknown"
    }
    
    // MARK: - Refresh Status
    
    /// Refresh the installation status of all components
    func refreshStatus() {
        state = .checking
        
        for i in components.indices {
            components[i].isInstalled = checkIfInstalled(components[i].component)
            if components[i].isInstalled {
                components[i].progress = 1.0
            }
        }
        
        let missing = components.filter { !$0.isInstalled }.map { $0.component }
        
        if missing.isEmpty {
            state = .completed
            hasCompletedSetup = true
        } else {
            state = .ready(missingComponents: missing)
        }
    }
    
    // MARK: - Download Management
    
    /// Download selected components
    func downloadComponents(_ selectedComponents: Set<SetupComponent>) async {
        state = .downloading
        
        for component in selectedComponents {
            currentDownload = component
            await downloadComponent(component)
        }
        
        currentDownload = nil
        refreshStatus()
    }
    
    /// Download a single component
    private func downloadComponent(_ component: SetupComponent) async {
        guard let index = components.firstIndex(where: { $0.component == component }) else { return }
        
        components[index].isDownloading = true
        components[index].progress = 0
        components[index].bytesDownloaded = 0
        components[index].error = nil
        
        do {
            try await downloadSoundFont()
            
            components[index].isInstalled = true
            components[index].progress = 1.0
            
        } catch {
            components[index].error = error
        }
        
        components[index].isDownloading = false
        updateOverallProgress()
    }
    
    /// Download SoundFont file
    private func downloadSoundFont() async throws {
        let destination = installPath(for: .soundFont)
        
        // Try each fallback URL
        for url in SetupComponent.soundFontFallbackURLs {
            do {
                let (tempURL, response) = try await URLSession.shared.download(from: url)
                
                // Check response
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode != 200 {
                    continue
                }
                
                // Move to destination
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tempURL, to: destination)
                
                return // Success
                
            } catch {
                // Try next URL
                continue
            }
        }
        
        throw SetupError.downloadFailed("Failed to download SoundFont from all mirrors")
    }
    
    private func updateOverallProgress() {
        let total = components.reduce(0.0) { $0 + $1.progress }
        overallProgress = total / Double(components.count)
    }
    
    // MARK: - Cancel Downloads
    
    func cancelAllDownloads() {
        for (_, task) in downloadTasks {
            task.cancel()
        }
        downloadTasks.removeAll()
        
        for i in components.indices {
            if components[i].isDownloading {
                components[i].isDownloading = false
                components[i].progress = 0
            }
        }
        
        refreshStatus()
    }
    
    // MARK: - Skip Setup
    
    /// Skip setup entirely (for development/testing)
    func skipSetup() {
        hasCompletedSetup = true
        state = .completed
    }
}

// MARK: - SetupError

enum SetupError: LocalizedError {
    case downloadFailed(String)
    case invalidComponent
    case insufficientDiskSpace(required: Int64, available: Int64)
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .invalidComponent:
            return "Invalid component configuration"
        case .insufficientDiskSpace(let required, let available):
            let req = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let avail = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Insufficient disk space. Required: \(req), Available: \(avail)"
        }
    }
}
