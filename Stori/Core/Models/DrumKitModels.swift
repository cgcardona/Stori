//
//  DrumKitModels.swift
//  Stori
//
//  Data models for drum kit sample packs
//

import Foundation

// MARK: - Drum Kit

/// A complete drum kit containing audio samples for each sound type
struct DrumKit: Identifiable, Codable {
    let id: UUID
    let name: String
    let author: String
    let license: String
    let version: String
    let sounds: [String: String]  // Maps sound type to filename
    let displayNames: [String: String]?  // Optional: Kit-specific display names (e.g., "cymbal" for crash)
    
    /// Directory containing this kit's files
    var directory: URL?
    
    enum CodingKeys: String, CodingKey {
        case id, name, author, license, version, sounds
        case displayNames = "display_names"
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        author: String,
        license: String = "CC0",
        version: String = "1.0",
        sounds: [String: String],
        displayNames: [String: String]? = nil,
        directory: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.license = license
        self.version = version
        self.sounds = sounds
        self.displayNames = displayNames
        self.directory = directory
    }
    
    /// Get the URL for a specific sound type
    func soundURL(for soundType: DrumSoundType) -> URL? {
        guard let directory = directory,
              let filename = sounds[soundType.rawValue] else {
            return nil
        }
        return directory.appendingPathComponent(filename)
    }
    
    /// Check if this kit has a sample for the given sound type
    func hasSound(for soundType: DrumSoundType) -> Bool {
        sounds[soundType.rawValue] != nil
    }
    
    /// List of available sound types in this kit
    var availableSounds: [DrumSoundType] {
        DrumSoundType.allCases.filter { hasSound(for: $0) }
    }
    
    /// Get the display name for a sound type (kit-specific or default)
    /// Example: CR-78 shows "Cymbal" instead of "Crash"
    func displayName(for soundType: DrumSoundType) -> String {
        // Check for kit-specific display name first
        if let kitName = displayNames?[soundType.rawValue] {
            return kitName
        }
        // Fall back to standard display name
        return soundType.displayName
    }
}

// MARK: - Kit Metadata (for JSON parsing)

/// Lightweight metadata structure matching kit.json format.
/// Backend kit.json may omit author/license; we default them for compatibility.
struct DrumKitMetadata: Codable {
    let name: String
    let author: String?
    let license: String?
    let version: String?
    let sounds: [String: String]
    let displayNames: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case name, author, license, version, sounds
        case displayNames = "display_names"
    }
    
    func toKit(id: UUID = UUID(), directory: URL) -> DrumKit {
        DrumKit(
            id: id,
            name: name,
            author: author ?? "Unknown",
            license: license ?? "CC0",
            version: version ?? "1.0",
            sounds: sounds,
            displayNames: displayNames,
            directory: directory
        )
    }
}

// MARK: - Placeholder Kit

extension DrumKit {
    /// Placeholder kit used during initialization before real kits are loaded
    /// Falls back to synthesized sounds if used during playback
    static let placeholder = DrumKit(
        name: "Loading...",
        author: "TellUrStori",
        license: "Built-in",
        version: "1.0",
        sounds: [:],  // Empty - uses synthesized fallback sounds
        directory: nil
    )
}

