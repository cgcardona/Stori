//
//  AddressValidator.swift
//  Stori
//
//  Real-time Ethereum address validation with checksum verification
//

import Foundation
import CryptoSwift

enum AddressValidation {
    case empty
    case typing
    case valid(checksumValid: Bool)
    case invalid(reason: String)
    case knownAddress(label: String)
    case suspicious(reason: String)
}

struct AddressValidator {
    
    /// Validates an Ethereum address
    static func validate(_ address: String) -> AddressValidation {
        // Empty
        if address.isEmpty {
            return .empty
        }
        
        // Still typing
        if address.count < 42 {
            return .typing
        }
        
        // Must start with 0x
        guard address.hasPrefix("0x") else {
            return .invalid(reason: "Address must start with 0x")
        }
        
        // Must be exactly 42 characters (0x + 40 hex chars)
        guard address.count == 42 else {
            return .invalid(reason: "Address must be 42 characters long")
        }
        
        // Must be valid hex
        let hexPart = String(address.dropFirst(2))
        guard hexPart.allSatisfy({ $0.isHexDigit }) else {
            return .invalid(reason: "Address contains invalid characters")
        }
        
        // Check if it's a known suspicious pattern
        if let suspiciousReason = checkSuspiciousPatterns(address) {
            return .suspicious(reason: suspiciousReason)
        }
        
        // Validate checksum (EIP-55)
        let checksumValid = validateChecksum(address)
        
        return .valid(checksumValid: checksumValid)
    }
    
    /// Validates EIP-55 checksum
    private static func validateChecksum(_ address: String) -> Bool {
        let hexAddress = String(address.dropFirst(2)).lowercased()
        let hash = hexAddress.data(using: .utf8)?.sha3(.keccak256).toHexString() ?? ""
        
        let addressChars = Array(address.dropFirst(2))
        let hashChars = Array(hash)
        
        for i in 0..<addressChars.count {
            let char = addressChars[i]
            let hashInt = Int(String(hashChars[i]), radix: 16) ?? 0
            
            if char.isLetter {
                if hashInt >= 8 && !char.isUppercase {
                    return false
                }
                if hashInt < 8 && !char.isLowercase {
                    return false
                }
            }
        }
        
        return true
    }
    
    /// Check for known suspicious address patterns
    private static func checkSuspiciousPatterns(_ address: String) -> String? {
        let lowercased = address.lowercased()
        
        // All zeros (burn address)
        if lowercased == "0x0000000000000000000000000000000000000000" {
            return "This is the burn address (0x0...0)"
        }
        
        // Known scam addresses (this would be a database in production)
        let knownScamAddresses: Set<String> = [
            // Add known scam addresses here
        ]
        
        if knownScamAddresses.contains(lowercased) {
            return "This address has been flagged as suspicious"
        }
        
        return nil
    }
    
    /// Converts address to checksum format (EIP-55)
    static func toChecksumAddress(_ address: String) -> String {
        guard address.hasPrefix("0x"), address.count == 42 else {
            return address
        }
        
        let hexAddress = String(address.dropFirst(2)).lowercased()
        let hash = hexAddress.data(using: .utf8)?.sha3(.keccak256).toHexString() ?? ""
        
        var checksumAddress = "0x"
        let addressChars = Array(hexAddress)
        let hashChars = Array(hash)
        
        for i in 0..<addressChars.count {
            let char = addressChars[i]
            let hashInt = Int(String(hashChars[i]), radix: 16) ?? 0
            
            if char.isLetter && hashInt >= 8 {
                checksumAddress.append(char.uppercased())
            } else {
                checksumAddress.append(char)
            }
        }
        
        return checksumAddress
    }
}

// MARK: - Address Book

struct AddressBookEntry: Identifiable, Codable {
    let id: UUID
    var label: String
    var address: String
    var color: String  // Hex color for visual identification
    var createdAt: Date
    var lastUsed: Date?
    
    init(label: String, address: String, color: String = "8B5CF6") {
        self.id = UUID()
        self.label = label
        self.address = address
        self.color = color
        self.createdAt = Date()
    }
    
    var initials: String {
        let words = label.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else {
            return String(label.prefix(2)).uppercased()
        }
    }
    
    var truncatedAddress: String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(8))...\(address.suffix(4))"
    }
}

@MainActor
@Observable
final class AddressBook {
    static let shared = AddressBook()
    
    private(set) var entries: [AddressBookEntry] = []
    private let storageKey = "addressBook"
    
    private init() {
        loadFromStorage()
    }
    
    func addEntry(label: String, address: String, color: String = "8B5CF6") {
        let entry = AddressBookEntry(label: label, address: address, color: color)
        entries.append(entry)
        saveToStorage()
    }
    
    func updateEntry(_ entry: AddressBookEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            saveToStorage()
        }
    }
    
    func deleteEntry(_ entry: AddressBookEntry) {
        entries.removeAll { $0.id == entry.id }
        saveToStorage()
    }
    
    func findEntry(for address: String) -> AddressBookEntry? {
        entries.first { $0.address.lowercased() == address.lowercased() }
    }
    
    func markAsUsed(_ entry: AddressBookEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].lastUsed = Date()
            saveToStorage()
        }
    }
    
    var recentlyUsed: [AddressBookEntry] {
        entries
            .filter { $0.lastUsed != nil }
            .sorted { ($0.lastUsed ?? Date.distantPast) > ($1.lastUsed ?? Date.distantPast) }
            .prefix(5)
            .map { $0 }
    }
    
    private func saveToStorage() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AddressBookEntry].self, from: data) {
            entries = decoded
        }
    }
    
    // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
    // No async resources owned.
    // No deinit required.
}
