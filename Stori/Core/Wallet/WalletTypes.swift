//
//  WalletTypes.swift
//  Stori
//
//  Core wallet types and protocols using battle-tested crypto libraries
//  NO CUSTOM CRYPTO - uses web3.swift, secp256k1.swift, CryptoSwift
//

import Foundation
import BigInt

// MARK: - Wallet Protocol

/// Protocol defining the core wallet interface
/// Implemented by both HDWallet (mnemonic-based) and SimpleWallet (single key)
protocol WalletProtocol {
    /// The primary Ethereum address (checksummed, EIP-55)
    var address: String { get }
    
    /// Whether this is a hierarchical deterministic wallet
    var isHDWallet: Bool { get }
    
    /// How this wallet was imported
    var importMethod: WalletImportMethod { get }
    
    /// Sign a message hash (32 bytes)
    func signHash(_ hash: Data) throws -> Data
    
    /// Get the private key data (use with caution!)
    func getPrivateKey() throws -> Data
}

// MARK: - Import Method

/// How the wallet was created/imported
enum WalletImportMethod: String, Codable {
    case created         // Generated new mnemonic
    case mnemonicImport  // Imported via mnemonic phrase
    case privateKey      // Imported via raw private key (dev/testing)
}

// MARK: - Mnemonic Language

/// Supported BIP-39 mnemonic languages
enum MnemonicLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "english"
    case spanish = "spanish"
    case french = "french"
    case italian = "italian"
    case portuguese = "portuguese"
    case japanese = "japanese"
    case korean = "korean"
    case chineseSimplified = "chinese_simplified"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .chineseSimplified: return "简体中文"
        }
    }
    
    /// Load the wordlist from bundle
    func loadWordlist() throws -> [String] {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "txt", subdirectory: "BIP39Wordlists") else {
            // Try alternate path
            guard let altUrl = Bundle.main.url(forResource: rawValue, withExtension: "txt") else {
                throw LocalWalletError.wordlistNotFound(rawValue)
            }
            return try loadWords(from: altUrl)
        }
        return try loadWords(from: url)
    }
    
    private func loadWords(from url: URL) throws -> [String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let words = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard words.count == 2048 else {
            throw LocalWalletError.invalidWordlist("Expected 2048 words, got \(words.count)")
        }
        
        return words
    }
}

// MARK: - Mnemonic Strength

/// BIP-39 mnemonic strength options
enum MnemonicStrength: Int, CaseIterable, Identifiable {
    case words12 = 128  // 12 words (128 bits entropy)
    case words15 = 160  // 15 words (160 bits entropy)
    case words18 = 192  // 18 words (192 bits entropy)
    case words21 = 224  // 21 words (224 bits entropy)
    case words24 = 256  // 24 words (256 bits entropy) - RECOMMENDED
    
    var id: Int { rawValue }
    
    var wordCount: Int {
        switch self {
        case .words12: return 12
        case .words15: return 15
        case .words18: return 18
        case .words21: return 21
        case .words24: return 24
        }
    }
    
    var displayName: String {
        "\(wordCount) words"
    }
    
    var securityLevel: String {
        switch self {
        case .words12: return "Standard"
        case .words15: return "Enhanced"
        case .words18: return "Strong"
        case .words21: return "Very Strong"
        case .words24: return "Maximum (Recommended)"
        }
    }
}

// MARK: - Blockchain Network

/// Supported blockchain networks
enum BlockchainNetwork: String, CaseIterable, Identifiable, Codable {
    case tellUrStoriLocal = "tellurstori_local"
    case tellUrStoriTestnet = "tellurstori_testnet"
    case tellUrStoriMainnet = "tellurstori_mainnet"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .tellUrStoriLocal: return "TellUrStori Local"
        case .tellUrStoriTestnet: return "TellUrStori Testnet"
        case .tellUrStoriMainnet: return "TellUrStori Mainnet"
        }
    }
    
    var chainId: Int {
        switch self {
        case .tellUrStoriLocal: return 507
        case .tellUrStoriTestnet: return 507
        case .tellUrStoriMainnet: return 507
        }
    }
    
    var rpcURL: URL {
        switch self {
        case .tellUrStoriLocal:
            // Stori L1 - deployed via avalanche-cli 2026-01-20
            // BlockchainID: AaBEDb6ANQ5uHFSmeGPsTZiwQiCz3nK9xDYW9c2UvnaT7ENGa
            return URL(string: "http://127.0.0.1:9654/ext/bc/AaBEDb6ANQ5uHFSmeGPsTZiwQiCz3nK9xDYW9c2UvnaT7ENGa/rpc")!
        case .tellUrStoriTestnet:
            return URL(string: "https://testnet-rpc.example.com/ext/bc/tellurstori/rpc")!
        case .tellUrStoriMainnet:
            return URL(string: "https://rpc.example.com/ext/bc/tellurstori/rpc")!
        }
    }
    
    var explorerURL: URL? {
        switch self {
        case .tellUrStoriLocal: return nil
        case .tellUrStoriTestnet: return URL(string: "https://testnet-explorer.example.com")
        case .tellUrStoriMainnet: return URL(string: "https://explorer.example.com")
        }
    }
    
    var nativeTokenSymbol: String { "TUS" }
    var nativeTokenName: String { "TellUrStori" }
    var nativeTokenDecimals: Int { 18 }
    
    var isTestnet: Bool {
        switch self {
        case .tellUrStoriLocal, .tellUrStoriTestnet: return true
        case .tellUrStoriMainnet: return false
        }
    }
}

// MARK: - Development Keys
// SECURITY: Hardcoded private keys have been removed from the codebase.
// For local development testing, use environment variables or a separate
// configuration file that is NOT committed to version control.
// 
// To use the Avalanche ewoq key for local testing:
// 1. Set STORI_DEV_PRIVATE_KEY environment variable
// 2. Or paste the key manually in the wallet import UI

// MARK: - Local Wallet Errors

/// Errors specific to the local wallet implementation
enum LocalWalletError: LocalizedError {
    case invalidMnemonic(String)
    case invalidPrivateKey(String)
    case invalidAddress(String)
    case invalidSignature
    case keyDerivationFailed(String)
    case signingFailed(String)
    case walletLocked
    case walletNotFound
    case keychainError(String)
    case biometricFailed
    case passwordIncorrect
    case networkError(String)
    case wordlistNotFound(String)
    case invalidWordlist(String)
    case entropyGenerationFailed
    case checksumMismatch
    
    var errorDescription: String? {
        switch self {
        case .invalidMnemonic(let msg): return "Invalid mnemonic: \(msg)"
        case .invalidPrivateKey(let msg): return "Invalid private key: \(msg)"
        case .invalidAddress(let msg): return "Invalid address: \(msg)"
        case .invalidSignature: return "Invalid signature format"
        case .keyDerivationFailed(let msg): return "Key derivation failed: \(msg)"
        case .signingFailed(let msg): return "Signing failed: \(msg)"
        case .walletLocked: return "Wallet is locked"
        case .walletNotFound: return "No wallet found"
        case .keychainError(let msg): return "Keychain error: \(msg)"
        case .biometricFailed: return "Biometric authentication failed"
        case .passwordIncorrect: return "Incorrect password"
        case .networkError(let msg): return "Network error: \(msg)"
        case .wordlistNotFound(let lang): return "Wordlist not found for language: \(lang)"
        case .invalidWordlist(let msg): return "Invalid wordlist: \(msg)"
        case .entropyGenerationFailed: return "Failed to generate secure random entropy"
        case .checksumMismatch: return "Mnemonic checksum verification failed"
        }
    }
}

/// Type alias for backwards compatibility
typealias WalletCoreError = LocalWalletError

// MARK: - Transaction Types

/// Transaction filter for history view
enum TransactionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case sent = "Sent"
    case received = "Received"
    case nftTransfer = "NFT"
    case contractCall = "Contract"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .sent: return "arrow.up.circle"
        case .received: return "arrow.down.circle"
        case .nftTransfer: return "photo"
        case .contractCall: return "doc.text"
        }
    }
}

/// A transaction in the history
struct WalletTransaction: Identifiable, Codable {
    let id: String  // Transaction hash
    let from: String
    let to: String
    let value: String  // In wei
    let gasUsed: String
    let gasPrice: String
    let timestamp: Date
    let blockNumber: Int
    let status: TransactionStatus
    let type: TransactionType
    let tokenId: String?  // For NFT transfers
    let contractAddress: String?  // For token/NFT transfers
    
    enum TransactionStatus: String, Codable {
        case pending
        case confirmed
        case failed
    }
    
    enum TransactionType: String, Codable {
        case nativeTransfer  // TUS transfer
        case nftTransfer     // ERC-721 or ERC-1155
        case contractCall    // Smart contract interaction
    }
    
    /// Formatted value in TUS (from wei)
    var formattedValue: String {
        guard let weiValue = BigUInt(value) else { return "0" }
        let tusValue = Double(weiValue) / 1e18
        if tusValue < 0.0001 && tusValue > 0 {
            return "<0.0001 TUS"
        }
        return String(format: "%.4f TUS", tusValue)
    }
    
    /// Shortened hash for display
    var shortHash: String {
        guard id.count > 12 else { return id }
        return "\(id.prefix(8))...\(id.suffix(4))"
    }
}

// MARK: - Security Level

/// Security level for keychain storage
enum WalletSecurityLevel: String, CaseIterable, Identifiable, Codable {
    case standard       // Keychain only
    case biometric      // Require Face ID/Touch ID
    case biometricStrict // Biometric + no fallback to passcode
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .biometric: return "Biometric (Recommended)"
        case .biometricStrict: return "Biometric Only"
        }
    }
    
    var description: String {
        switch self {
        case .standard:
            return "Protected by your device passcode"
        case .biometric:
            return "Requires Face ID or Touch ID, with passcode fallback"
        case .biometricStrict:
            return "Requires Face ID or Touch ID only, no passcode fallback"
        }
    }
}
