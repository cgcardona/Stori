//
//  AssetModels.swift
//  Stori
//
//  Codable models for on-demand asset API (drum kits, SoundFonts).
//

import Foundation

// MARK: - List Responses (API)

/// Drum kit item from GET /api/v1/assets/drum-kits
struct DrumKitItem: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let fileCount: Int?
}

/// SoundFont item from GET /api/v1/assets/soundfonts
struct SoundFontItem: Codable, Identifiable {
    let id: String
    let name: String
    let filename: String
}

/// Response from GET .../download-url (drum-kit, soundfont, or bundle)
/// Note: Decoder uses .convertFromSnakeCase, so expires_at in JSON maps to expiresAt in Swift
struct DownloadURLResponse: Codable {
    let url: String
    let expiresAt: String  // Required field; decoder will convert expires_at automatically
}

// MARK: - Download Errors

enum AssetDownloadError: LocalizedError {
    case invalidURL
    case notFound
    case unauthorized
    case serviceUnavailable
    case network(Error)
    case unzipFailed
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid download URL."
        case .notFound: return "This pack is not available."
        case .unauthorized: return "Could not load from server. Please try again later."
        case .serviceUnavailable: return "Asset service unavailable. Try again later."
        case .network(let e): 
            // Remove server URL from user-facing network errors
            let message = e.localizedDescription
            #if DEBUG
            return "Download failed: \(message)"
            #else
            // Strip server URL if present in production
            return message.replacingOccurrences(of: " \\(server:.*\\)", with: "", options: .regularExpression)
            #endif
        case .unzipFailed: return "Failed to extract the drum kit."
        case .fileWriteFailed: return "Failed to save the file."
        }
    }
}
