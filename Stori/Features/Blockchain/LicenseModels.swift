//
//  LicenseModels.swift
//  Stori
//
//  Created by TellUrStori on 12/9/25.
//

import SwiftUI

// MARK: - License Type Enum

/// The 5 license types supported by the DigitalInstanceFactory contract
enum LicenseType: Int, CaseIterable, Identifiable {
    case fullOwnership = 0
    case streaming = 1
    case limitedPlay = 2
    case timeLimited = 3
    case commercialLicense = 4
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .fullOwnership: return "Full Ownership"
        case .streaming: return "Streaming"
        case .limitedPlay: return "Limited Play"
        case .timeLimited: return "Time Limited"
        case .commercialLicense: return "Commercial License"
        }
    }
    
    var icon: String {
        switch self {
        case .fullOwnership: return "💎"
        case .streaming: return "🎧"
        case .limitedPlay: return "🎫"
        case .timeLimited: return "⏰"
        case .commercialLicense: return "🏢"
        }
    }
    
    var systemIcon: String {
        switch self {
        case .fullOwnership: return "diamond.fill"
        case .streaming: return "headphones"
        case .limitedPlay: return "ticket.fill"
        case .timeLimited: return "clock.fill"
        case .commercialLicense: return "building.2.fill"
        }
    }
    
    var description: String {
        switch self {
        case .fullOwnership:
            return "Complete ownership with download and resale rights"
        case .streaming:
            return "Pay-per-stream micropayments"
        case .limitedPlay:
            return "Fixed number of plays before expiration"
        case .timeLimited:
            return "Access for a fixed time period"
        case .commercialLicense:
            return "Rights for commercial use (sync, broadcast, etc.)"
        }
    }
    
    var bestFor: String {
        switch self {
        case .fullOwnership:
            return "Collectors, fans who want to own the music"
        case .streaming:
            return "Casual listeners, discovery"
        case .limitedPlay:
            return "Try-before-you-buy, promotional"
        case .timeLimited:
            return "Rentals, subscriptions, previews"
        case .commercialLicense:
            return "Businesses, content creators, advertisers"
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .fullOwnership: return [.purple, .pink]
        case .streaming: return [.blue, .cyan]
        case .limitedPlay: return [.orange, .yellow]
        case .timeLimited: return [.green, .mint]
        case .commercialLicense: return [.indigo, .purple]
        }
    }
    
    var accentColor: Color {
        switch self {
        case .fullOwnership: return .purple
        case .streaming: return .blue
        case .limitedPlay: return .orange
        case .timeLimited: return .green
        case .commercialLicense: return .indigo
        }
    }
    
    var rights: [String] {
        switch self {
        case .fullOwnership:
            return [
                "Full ownership of this license",
                "Download and store locally",
                "Transfer or resell to others",
                "Unlimited personal playback"
            ]
        case .streaming:
            return [
                "Stream on-demand",
                "Pay only for what you listen to",
                "No download rights"
            ]
        case .limitedPlay:
            return [
                "Limited number of plays",
                "Personal use only",
                "No download or transfer rights"
            ]
        case .timeLimited:
            return [
                "Access for the license duration",
                "Unlimited plays during period",
                "No download or transfer rights"
            ]
        case .commercialLicense:
            return [
                "Use in commercial projects",
                "Sync to video/film/ads",
                "Broadcast rights included",
                "Credit required per terms"
            ]
        }
    }
}

// MARK: - License Configuration

/// Configuration for creating a new license instance
struct LicenseConfiguration {
    var licenseType: LicenseType = .fullOwnership
    
    // Common parameters
    var price: Double = 0.5
    var maxSupply: Int = 100  // 0 = unlimited
    var isTransferable: Bool = true
    
    // Streaming specific
    var pricePerStream: Double = 0.001
    
    // Limited Play specific
    var playsIncluded: Int = 10
    
    // Time Limited specific
    var durationDays: Int = 30
    
    // Commercial License specific
    var commercialTerms: String = ""
    
    /// Platform fee percentage (1%)
    static let platformFeePercent: Double = 1.0
    
    /// Calculate creator revenue per sale
    func creatorRevenuePerSale(royaltyPercent: Int) -> Double {
        let afterPlatform = price * (1 - Self.platformFeePercent / 100)
        let afterRoyalty = afterPlatform * (1 - Double(royaltyPercent) / 100)
        return afterRoyalty
    }
    
    /// Calculate potential total revenue
    func potentialRevenue(royaltyPercent: Int) -> Double {
        guard maxSupply > 0 else { return 0 } // Unlimited
        return creatorRevenuePerSale(royaltyPercent: royaltyPercent) * Double(maxSupply)
    }
    
    /// Convert to contract parameters
    func toContractParams() -> [String: Any] {
        var params: [String: Any] = [
            "licenseType": licenseType.rawValue,
            "price": priceToWei(price),
            "maxSupply": maxSupply,
            "isTransferable": isTransferable
        ]
        
        switch licenseType {
        case .streaming:
            params["pricePerStream"] = priceToWei(pricePerStream)
        case .limitedPlay:
            params["playsIncluded"] = playsIncluded
        case .timeLimited:
            params["durationDays"] = durationDays
        case .commercialLicense:
            params["commercialTerms"] = commercialTerms
        default:
            break
        }
        
        return params
    }
    
    /// Convert TUS to wei (18 decimals)
    private func priceToWei(_ tus: Double) -> String {
        let wei = tus * 1_000_000_000_000_000_000
        return String(format: "%.0f", wei)
    }
}

// MARK: - License Instance Model

/// Represents a created license instance
struct LicenseInstance: Identifiable {
    let id: String
    let instanceId: String
    let masterId: String
    let licenseType: LicenseType
    let price: Double
    let maxSupply: Int
    let totalMinted: Int
    let isTransferable: Bool
    let metadataURI: String?
    let createdAt: Date
    let transactionHash: String
    
    var remainingSupply: Int {
        guard maxSupply > 0 else { return -1 } // Unlimited
        return maxSupply - totalMinted
    }
    
    var isAvailable: Bool {
        guard maxSupply > 0 else { return true } // Unlimited
        return totalMinted < maxSupply
    }
    
    var soldPercentage: Double {
        guard maxSupply > 0 else { return 0 }
        return Double(totalMinted) / Double(maxSupply) * 100
    }
}

// MARK: - Mock Data

extension LicenseInstance {
    static let mockData: [LicenseInstance] = [
        LicenseInstance(
            id: "1",
            instanceId: "0x001",
            masterId: "0x4d5e6f",
            licenseType: .fullOwnership,
            price: 0.5,
            maxSupply: 100,
            totalMinted: 35,
            isTransferable: true,
            metadataURI: "ipfs://Qm...",
            createdAt: Date().addingTimeInterval(-86400 * 10),
            transactionHash: "0xabc..."
        ),
        LicenseInstance(
            id: "2",
            instanceId: "0x002",
            masterId: "0x4d5e6f",
            licenseType: .streaming,
            price: 0.001,
            maxSupply: 0, // Unlimited
            totalMinted: 1234,
            isTransferable: false,
            metadataURI: "ipfs://Qm...",
            createdAt: Date().addingTimeInterval(-86400 * 5),
            transactionHash: "0xdef..."
        ),
        LicenseInstance(
            id: "3",
            instanceId: "0x003",
            masterId: "0x4d5e6f",
            licenseType: .limitedPlay,
            price: 0.1,
            maxSupply: 500,
            totalMinted: 127,
            isTransferable: true,
            metadataURI: "ipfs://Qm...",
            createdAt: Date().addingTimeInterval(-86400 * 3),
            transactionHash: "0xghi..."
        )
    ]
}

