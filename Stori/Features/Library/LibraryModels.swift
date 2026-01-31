//
//  LibraryModels.swift
//  Stori
//
//  Created by TellUrStori on 12/10/25.
//

import Foundation
import SwiftUI

// MARK: - Purchased License

/// Represents a license instance owned by the user
struct PurchasedLicense: Identifiable, Hashable {
    let id: String
    let instanceId: String
    let masterId: String
    let tokenId: String
    
    // Content Info
    let title: String
    let artistName: String
    let description: String
    let imageURL: URL?
    let audioURI: String?
    
    // License Details
    let licenseType: LicenseType
    let purchaseDate: Date
    let purchasePrice: Double
    let transactionHash: String
    
    // License State
    var playsRemaining: Int?
    var totalPlays: Int?
    var expirationDate: Date?
    var isTransferable: Bool
    
    // Computed Properties
    var isExpired: Bool {
        guard let expiration = expirationDate else { return false }
        return Date() > expiration
    }
    
    var daysRemaining: Int? {
        guard let expiration = expirationDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expiration)
        return max(0, components.day ?? 0)
    }
    
    var playProgress: Double? {
        guard let remaining = playsRemaining, let total = totalPlays, total > 0 else { return nil }
        return Double(total - remaining) / Double(total)
    }
    
    var accessState: LicenseAccessState {
        if isExpired {
            return .expired
        }
        if let remaining = playsRemaining, remaining <= 0 {
            return .exhausted
        }
        if let days = daysRemaining, days <= 3 {
            return .expiringSoon
        }
        if let remaining = playsRemaining, let total = totalPlays, remaining <= total / 4 {
            return .lowPlays
        }
        return .active
    }
    
    // MARK: - Mock Data
    
    static let mockData: [PurchasedLicense] = [
        PurchasedLicense(
            id: "pl-1",
            instanceId: "1",
            masterId: "1",
            tokenId: "1",
            title: "Electric Soul",
            artistName: "TellUrStori",
            description: "A vibrant electronic track with soulful undertones",
            imageURL: nil,
            audioURI: "ipfs://QmAudio1",
            licenseType: .fullOwnership,
            purchaseDate: Date().addingTimeInterval(-86400 * 7),
            purchasePrice: 2.5,
            transactionHash: "0xabc123",
            playsRemaining: nil,
            totalPlays: nil,
            expirationDate: nil,
            isTransferable: true
        ),
        PurchasedLicense(
            id: "pl-2",
            instanceId: "2",
            masterId: "2",
            tokenId: "2",
            title: "Midnight Groove",
            artistName: "NightOwl",
            description: "Deep house vibes for late night sessions",
            imageURL: nil,
            audioURI: "ipfs://QmAudio2",
            licenseType: .streaming,
            purchaseDate: Date().addingTimeInterval(-86400 * 3),
            purchasePrice: 0.1,
            transactionHash: "0xdef456",
            playsRemaining: nil,
            totalPlays: nil,
            expirationDate: nil,
            isTransferable: false
        ),
        PurchasedLicense(
            id: "pl-3",
            instanceId: "3",
            masterId: "3",
            tokenId: "3",
            title: "Sunset Drive",
            artistName: "Coastal",
            description: "Chill beats for the open road",
            imageURL: nil,
            audioURI: "ipfs://QmAudio3",
            licenseType: .limitedPlay,
            purchaseDate: Date().addingTimeInterval(-86400 * 1),
            purchasePrice: 0.25,
            transactionHash: "0xghi789",
            playsRemaining: 7,
            totalPlays: 10,
            expirationDate: nil,
            isTransferable: false
        ),
        PurchasedLicense(
            id: "pl-4",
            instanceId: "4",
            masterId: "4",
            tokenId: "4",
            title: "Urban Beats",
            artistName: "CitySound",
            description: "Hip-hop inspired instrumentals",
            imageURL: nil,
            audioURI: "ipfs://QmAudio4",
            licenseType: .timeLimited,
            purchaseDate: Date().addingTimeInterval(-86400 * 5),
            purchasePrice: 0.5,
            transactionHash: "0xjkl012",
            playsRemaining: nil,
            totalPlays: nil,
            expirationDate: Date().addingTimeInterval(86400 * 25),
            isTransferable: false
        ),
        PurchasedLicense(
            id: "pl-5",
            instanceId: "5",
            masterId: "5",
            tokenId: "5",
            title: "Film Score Suite",
            artistName: "Orchestra Pro",
            description: "Cinematic compositions for commercial use",
            imageURL: nil,
            audioURI: "ipfs://QmAudio5",
            licenseType: .commercialLicense,
            purchaseDate: Date().addingTimeInterval(-86400 * 14),
            purchasePrice: 25.0,
            transactionHash: "0xmno345",
            playsRemaining: nil,
            totalPlays: nil,
            expirationDate: nil,
            isTransferable: true
        )
    ]
}

// MARK: - License Access State

/// The current access state of a purchased license
enum LicenseAccessState {
    case active
    case lowPlays
    case expiringSoon
    case expired
    case exhausted
    
    var color: Color {
        switch self {
        case .active: return .green
        case .lowPlays: return .orange
        case .expiringSoon: return .orange
        case .expired: return .red
        case .exhausted: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .lowPlays: return "exclamationmark.triangle.fill"
        case .expiringSoon: return "clock.badge.exclamationmark"
        case .expired: return "xmark.circle.fill"
        case .exhausted: return "stop.circle.fill"
        }
    }
    
    var label: String {
        switch self {
        case .active: return "Active"
        case .lowPlays: return "Low Plays"
        case .expiringSoon: return "Expiring Soon"
        case .expired: return "Expired"
        case .exhausted: return "No Plays Left"
        }
    }
}

// MARK: - Playback State

/// Tracks the current playback state for a license
struct PlaybackState {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 1.0
    var isMuted: Bool = false
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var timeRemaining: TimeInterval {
        return max(0, duration - currentTime)
    }
    
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    var formattedDuration: String {
        formatTime(duration)
    }
    
    var formattedTimeRemaining: String {
        formatTime(timeRemaining)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - License Access Control

/// Defines what actions are allowed for each license type
struct LicenseAccessControl {
    let licenseType: LicenseType
    
    var canDownload: Bool {
        switch licenseType {
        case .fullOwnership, .commercialLicense:
            return true
        case .timeLimited:
            return true // Optional download with DRM
        case .streaming, .limitedPlay:
            return false
        }
    }
    
    var canResell: Bool {
        switch licenseType {
        case .fullOwnership:
            return true
        case .commercialLicense:
            return true // With terms
        default:
            return false
        }
    }
    
    var hasUnlimitedPlays: Bool {
        switch licenseType {
        case .fullOwnership, .streaming, .timeLimited, .commercialLicense:
            return true
        case .limitedPlay:
            return false
        }
    }
    
    var hasExpiration: Bool {
        switch licenseType {
        case .timeLimited:
            return true
        default:
            return false
        }
    }
    
    var downloadFormat: String? {
        switch licenseType {
        case .fullOwnership:
            return "HQ WAV"
        case .commercialLicense:
            return "Master WAV + STEMs"
        case .timeLimited:
            return "Protected MP3"
        default:
            return nil
        }
    }
    
    var rightsDescription: [String] {
        switch licenseType {
        case .fullOwnership:
            return [
                "Unlimited streaming & offline playback",
                "Download HQ WAV file",
                "Resell on marketplace",
                "Personal use only"
            ]
        case .streaming:
            return [
                "Unlimited streaming",
                "Access on all devices",
                "Support artist directly"
            ]
        case .limitedPlay:
            return [
                "Set number of plays",
                "Track your listening",
                "Auto-expires when used"
            ]
        case .timeLimited:
            return [
                "Unlimited plays during period",
                "Optional offline download",
                "Access expires after duration"
            ]
        case .commercialLicense:
            return [
                "Commercial use rights",
                "Sync licensing included",
                "Download master files",
                "Full stems access"
            ]
        }
    }
}

// MARK: - Library Sort Options

enum LibrarySortOption: String, CaseIterable {
    case recentlyPurchased = "Recently Purchased"
    case title = "Title"
    case artist = "Artist"
    case licenseType = "License Type"
    
    var icon: String {
        switch self {
        case .recentlyPurchased: return "clock"
        case .title: return "textformat"
        case .artist: return "person"
        case .licenseType: return "tag"
        }
    }
}

// MARK: - Library Filter Options

enum LibraryFilterOption: String, CaseIterable {
    case all = "All"
    case fullOwnership = "Full Ownership"
    case streaming = "Streaming"
    case limitedPlay = "Limited Play"
    case timeLimited = "Time Limited"
    case commercial = "Commercial"
    
    var licenseType: LicenseType? {
        switch self {
        case .all: return nil
        case .fullOwnership: return .fullOwnership
        case .streaming: return .streaming
        case .limitedPlay: return .limitedPlay
        case .timeLimited: return .timeLimited
        case .commercial: return .commercialLicense
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .fullOwnership: return "crown.fill"
        case .streaming: return "music.note.tv"
        case .limitedPlay: return "number.circle"
        case .timeLimited: return "clock"
        case .commercial: return "building.2"
        }
    }
}

