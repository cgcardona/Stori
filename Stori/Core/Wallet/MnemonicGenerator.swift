//
//  MnemonicGenerator.swift
//  Stori
//
//  BIP-39 mnemonic generation and validation
//  Uses CryptoSwift for hashing - NO CUSTOM CRYPTO
//

import Foundation
import CryptoSwift
import Security

// MARK: - Mnemonic Generator

/// BIP-39 compliant mnemonic generator supporting 8 languages
final class MnemonicGenerator {
    
    // MARK: - Properties
    
    let language: MnemonicLanguage
    private var wordlist: [String]?
    private var wordToIndex: [String: Int]?
    
    // MARK: - Initialization
    
    init(language: MnemonicLanguage = .english) {
        self.language = language
    }
    
    // MARK: - Wordlist Loading
    
    /// Get the wordlist, loading from bundle if needed
    func getWordlist() throws -> [String] {
        if let existing = wordlist {
            return existing
        }
        
        let words = try language.loadWordlist()
        self.wordlist = words
        self.wordToIndex = Dictionary(uniqueKeysWithValues: words.enumerated().map { ($1, $0) })
        return words
    }
    
    // MARK: - Mnemonic Generation
    
    /// Generate a new mnemonic with the specified strength
    /// - Parameter strength: Number of bits of entropy (128, 160, 192, 224, or 256)
    /// - Returns: Array of mnemonic words
    func generate(strength: MnemonicStrength = .words24) throws -> [String] {
        let entropyBytes = strength.rawValue / 8
        
        // Generate secure random entropy using Apple's Security framework
        var entropy = Data(count: entropyBytes)
        let result = entropy.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, entropyBytes, bytes.baseAddress!)
        }
        
        guard result == errSecSuccess else {
            throw LocalWalletError.entropyGenerationFailed
        }
        
        return try entropyToMnemonic(entropy)
    }
    
    /// Convert entropy to mnemonic words
    /// - Parameter entropy: Random entropy data (16, 20, 24, 28, or 32 bytes)
    /// - Returns: Array of mnemonic words
    func entropyToMnemonic(_ entropy: Data) throws -> [String] {
        let words = try getWordlist()
        
        // Calculate checksum
        let hash = entropy.sha256()
        let checksumBits = entropy.count / 4  // CS = ENT / 32, but in bits = ENT_bytes / 4
        
        // Combine entropy + checksum bits
        var bits = entropy.toBitArray()
        let hashBits = hash.toBitArray()
        bits.append(contentsOf: hashBits.prefix(checksumBits))
        
        // Split into 11-bit groups and convert to words
        let wordCount = bits.count / 11
        var mnemonic: [String] = []
        
        for i in 0..<wordCount {
            let startIndex = i * 11
            let endIndex = startIndex + 11
            let indexBits = Array(bits[startIndex..<endIndex])
            let wordIndex = indexBits.toInt()
            
            guard wordIndex < words.count else {
                throw LocalWalletError.invalidMnemonic("Word index out of range: \(wordIndex)")
            }
            
            mnemonic.append(words[wordIndex])
        }
        
        return mnemonic
    }
    
    // MARK: - Mnemonic Validation
    
    /// Validate a mnemonic phrase
    /// - Parameter mnemonic: Array of mnemonic words
    /// - Returns: True if valid
    func validate(_ mnemonic: [String]) -> Bool {
        do {
            _ = try mnemonicToEntropy(mnemonic)
            return true
        } catch {
            return false
        }
    }
    
    /// Convert mnemonic back to entropy (validates checksum)
    /// - Parameter mnemonic: Array of mnemonic words
    /// - Returns: Original entropy data
    func mnemonicToEntropy(_ mnemonic: [String]) throws -> Data {
        let words = try getWordlist()
        
        guard let wordToIndex = self.wordToIndex else {
            throw LocalWalletError.wordlistNotFound(language.rawValue)
        }
        
        // Validate word count
        guard [12, 15, 18, 21, 24].contains(mnemonic.count) else {
            throw LocalWalletError.invalidMnemonic("Invalid word count: \(mnemonic.count)")
        }
        
        // Convert words to bits
        var bits: [Bool] = []
        for word in mnemonic {
            let normalized = word.lowercased().trimmingCharacters(in: .whitespaces)
            
            // Apply NFKD normalization for non-ASCII languages
            let normalizedWord = normalized.precomposedStringWithCompatibilityMapping
            
            guard let index = wordToIndex[normalizedWord] ?? wordToIndex[normalized] else {
                throw LocalWalletError.invalidMnemonic("Unknown word: \(word)")
            }
            
            // Convert index to 11 bits
            for j in (0..<11).reversed() {
                bits.append((index >> j) & 1 == 1)
            }
        }
        
        // Split into entropy and checksum
        let checksumBits = mnemonic.count / 3  // 1 bit per 3 words
        let entropyBits = bits.count - checksumBits
        
        let entropyBitArray = Array(bits.prefix(entropyBits))
        let checksumBitArray = Array(bits.suffix(checksumBits))
        
        // Convert entropy bits to bytes
        let entropy = Data(entropyBitArray.toBytes())
        
        // Verify checksum
        let hash = entropy.sha256()
        let hashBits = hash.toBitArray()
        let expectedChecksum = Array(hashBits.prefix(checksumBits))
        
        guard checksumBitArray == expectedChecksum else {
            throw LocalWalletError.checksumMismatch
        }
        
        return entropy
    }
    
    // MARK: - Seed Generation
    
    /// Convert mnemonic to seed using PBKDF2
    /// - Parameters:
    ///   - mnemonic: Array of mnemonic words
    ///   - passphrase: Optional passphrase (BIP-39 extension)
    /// - Returns: 64-byte seed
    func mnemonicToSeed(_ mnemonic: [String], passphrase: String = "") throws -> Data {
        // Normalize mnemonic (NFKD)
        let normalizedMnemonic = mnemonic
            .map { $0.precomposedStringWithCompatibilityMapping }
            .joined(separator: " ")
        
        // Salt is "mnemonic" + passphrase (NFKD normalized)
        let salt = "mnemonic" + passphrase.precomposedStringWithCompatibilityMapping
        
        // PBKDF2 with HMAC-SHA512, 2048 iterations, 64 byte output
        // Uses CryptoSwift's implementation
        guard let mnemonicData = normalizedMnemonic.data(using: .utf8),
              let saltData = salt.data(using: .utf8) else {
            throw LocalWalletError.invalidMnemonic("Failed to encode mnemonic")
        }
        
        do {
            let seed = try PKCS5.PBKDF2(
                password: Array(mnemonicData),
                salt: Array(saltData),
                iterations: 2048,
                keyLength: 64,
                variant: .sha2(.sha512)
            ).calculate()
            
            return Data(seed)
        } catch {
            throw LocalWalletError.keyDerivationFailed("PBKDF2 failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Bit Array Extensions

private extension Data {
    /// Convert data to array of bits
    func toBitArray() -> [Bool] {
        var bits: [Bool] = []
        for byte in self {
            for i in (0..<8).reversed() {
                bits.append((byte >> i) & 1 == 1)
            }
        }
        return bits
    }
}

private extension Array where Element == Bool {
    /// Convert 11-bit array to integer
    func toInt() -> Int {
        var value = 0
        for bit in self {
            value = (value << 1) | (bit ? 1 : 0)
        }
        return value
    }
    
    /// Convert bit array to bytes
    func toBytes() -> [UInt8] {
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        
        for (index, bit) in self.enumerated() {
            let bitPosition = 7 - (index % 8)
            if bit {
                byte |= (1 << bitPosition)
            }
            
            if (index + 1) % 8 == 0 {
                bytes.append(byte)
                byte = 0
            }
        }
        
        return bytes
    }
}
