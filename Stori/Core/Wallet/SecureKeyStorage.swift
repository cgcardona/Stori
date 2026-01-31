//
//  SecureKeyStorage.swift
//  Stori
//
//  Secure Keychain storage for wallet credentials
//  Uses KeychainAccess library + Apple's LocalAuthentication
//

import Foundation
import KeychainAccess
import LocalAuthentication
import CryptoSwift

// MARK: - Secure Key Storage

/// Manages secure storage of wallet credentials in the macOS Keychain
/// Supports biometric authentication (Touch ID / Face ID)
final class SecureKeyStorage {
    
    // MARK: - Constants
    
    private static let serviceName = "com.tellurstori.stori.wallet"
    private static let seedKey = "wallet_seed"
    private static let mnemonicKey = "wallet_mnemonic"
    private static let privateKeyKey = "wallet_private_key"
    private static let metadataKey = "wallet_metadata"
    private static let saltKey = "wallet_salt"
    
    // MARK: - Singleton
    
    static let shared = SecureKeyStorage()
    
    // MARK: - Properties
    
    private let keychain: Keychain
    
    // MARK: - Initialization
    
    private init() {
        // Use a simple keychain configuration that works without code signing
        // For development, we use service-only keychain without access groups
        // This avoids the "application-identifier" entitlement error
        self.keychain = Keychain(service: Self.serviceName)
            .synchronizable(false)  // Don't sync to iCloud for security
            .accessibility(.afterFirstUnlock)  // Use less restrictive accessibility for dev
    }
    
    // MARK: - Store Operations
    
    /// Store an HD wallet's mnemonic securely
    /// - Parameters:
    ///   - mnemonic: Array of mnemonic words
    ///   - password: User's password for additional encryption
    ///   - security: Security level (standard, biometric, biometricStrict)
    func storeMnemonic(
        _ mnemonic: [String],
        password: String,
        security: WalletSecurityLevel = .biometric
    ) async throws {
        let mnemonicString = mnemonic.joined(separator: " ")
        
        // Encrypt with password
        let encrypted = try encrypt(mnemonicString, password: password)
        
        // Store in keychain with appropriate security
        let keychain = configuredKeychain(for: security)
        
        try keychain.set(encrypted.ciphertext, key: Self.mnemonicKey)
        try keychain.set(encrypted.salt, key: Self.saltKey)
        
        // Store metadata
        let metadata = WalletMetadata(
            createdAt: Date(),
            importMethod: .created,
            securityLevel: security,
            isHDWallet: true
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try keychain.set(metadataData, key: Self.metadataKey)
    }
    
    /// Store a private key securely (for SimpleWallet)
    /// - Parameters:
    ///   - privateKey: 32-byte private key
    ///   - password: User's password for additional encryption
    ///   - security: Security level
    func storePrivateKey(
        _ privateKey: Data,
        password: String,
        security: WalletSecurityLevel = .biometric
    ) async throws {
        let hexKey = privateKey.map { String(format: "%02x", $0) }.joined()
        
        // Encrypt with password
        let encrypted = try encrypt(hexKey, password: password)
        
        // Store in keychain
        let keychain = configuredKeychain(for: security)
        
        try keychain.set(encrypted.ciphertext, key: Self.privateKeyKey)
        try keychain.set(encrypted.salt, key: Self.saltKey)
        
        // Store metadata
        let metadata = WalletMetadata(
            createdAt: Date(),
            importMethod: .privateKey,
            securityLevel: security,
            isHDWallet: false
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try keychain.set(metadataData, key: Self.metadataKey)
    }
    
    // MARK: - Retrieve Operations
    
    /// Retrieve and decrypt the stored mnemonic
    /// - Parameter password: User's password
    /// - Returns: Array of mnemonic words
    func retrieveMnemonic(password: String) async throws -> [String] {
        // Use consistent keychain access (same as store operations in DEBUG)
        #if DEBUG
        let readKeychain = keychain.accessibility(.afterFirstUnlock)
        #else
        let readKeychain = keychain
        #endif
        
        guard let ciphertext = try readKeychain.getData(Self.mnemonicKey),
              let salt = try readKeychain.getData(Self.saltKey) else {
            throw LocalWalletError.walletNotFound
        }
        
        let decrypted = try decrypt(ciphertext: ciphertext, salt: salt, password: password)
        return decrypted.components(separatedBy: " ")
    }
    
    /// Retrieve and decrypt the stored private key
    /// - Parameter password: User's password
    /// - Returns: 32-byte private key
    func retrievePrivateKey(password: String) async throws -> Data {
        // Use consistent keychain access (same as store operations in DEBUG)
        #if DEBUG
        let readKeychain = keychain.accessibility(.afterFirstUnlock)
        #else
        let readKeychain = keychain
        #endif
        
        guard let ciphertext = try readKeychain.getData(Self.privateKeyKey),
              let salt = try readKeychain.getData(Self.saltKey) else {
            throw LocalWalletError.walletNotFound
        }
        
        let hexKey = try decrypt(ciphertext: ciphertext, salt: salt, password: password)
        
        guard let keyData = Data(hexString: hexKey) else {
            throw LocalWalletError.keychainError("Failed to decode private key")
        }
        
        return keyData
    }
    
    // MARK: - Query Operations
    
    /// Check if a wallet is stored
    var hasStoredWallet: Bool {
        do {
            let hasMnemonic = try keychain.contains(Self.mnemonicKey)
            let hasPrivateKey = try keychain.contains(Self.privateKeyKey)
            return hasMnemonic || hasPrivateKey
        } catch {
            return false
        }
    }
    
    /// Get stored wallet metadata
    func getMetadata() throws -> WalletMetadata? {
        guard let data = try keychain.getData(Self.metadataKey) else {
            return nil
        }
        return try JSONDecoder().decode(WalletMetadata.self, from: data)
    }
    
    // MARK: - Delete Operations
    
    /// Delete all stored wallet data
    /// WARNING: This permanently deletes the wallet!
    func deleteWallet() throws {
        // Remove all keys, ignoring errors for keys that don't exist
        try? keychain.remove(Self.mnemonicKey)
        try? keychain.remove(Self.privateKeyKey)
        try? keychain.remove(Self.saltKey)
        try? keychain.remove(Self.metadataKey)
        try? keychain.remove(Self.seedKey)
        
        // Also try removing all items in the service
        try? keychain.removeAll()
    }
    
    // MARK: - Biometric Authentication
    
    /// Check if biometric authentication is available
    var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Get the type of biometric authentication available
    var biometricType: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Biometric"
        }
    }
    
    /// Authenticate with biometrics
    /// - Parameter reason: Reason to show to user
    /// - Returns: True if authenticated
    func authenticateWithBiometrics(reason: String = "Authenticate to access your wallet") async throws -> Bool {
        let context = LAContext()
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            throw LocalWalletError.biometricFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if let error = error {
                    continuation.resume(throwing: LocalWalletError.biometricFailed)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Configure keychain with security level
    private func configuredKeychain(for security: WalletSecurityLevel) -> Keychain {
        // For development without proper code signing, use standard keychain
        // The authenticationPolicy options require proper entitlements
        #if DEBUG
        // In debug mode, use simpler keychain without biometric requirements
        // This avoids entitlement issues during development
        return keychain.accessibility(.afterFirstUnlock)
        #else
        switch security {
        case .standard:
            return keychain
                .accessibility(.whenUnlockedThisDeviceOnly)
            
        case .biometric:
            return keychain
                .accessibility(.whenUnlockedThisDeviceOnly, authenticationPolicy: .userPresence)
                .authenticationPrompt("Authenticate to access your wallet")
            
        case .biometricStrict:
            return keychain
                .accessibility(.whenUnlockedThisDeviceOnly, authenticationPolicy: .biometryCurrentSet)
                .authenticationPrompt("Authenticate with biometrics to access your wallet")
        }
        #endif
    }
    
    /// Encrypt data with password using AES-256-GCM
    /// Returns blob = IV (12 bytes) + ciphertext + authentication tag (16 bytes)
    private func encrypt(_ plaintext: String, password: String) throws -> (ciphertext: Data, salt: Data) {
        #if DEBUG
        // SECURITY: Never log password values, only metadata
        #endif
        
        // Generate random salt
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        
        // Derive key using PBKDF2
        let key = try deriveKey(password: password, salt: salt)
        
        #if DEBUG
        #endif
        
        // Generate random IV
        var iv = Data(count: 12)  // 96 bits for GCM
        _ = iv.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 12, bytes.baseAddress!)
        }
        
        // Encrypt with AES-GCM in detached mode to get the authentication tag separately
        var gcm = GCM(iv: Array(iv), mode: .detached)
        let aes = try AES(key: Array(key), blockMode: gcm, padding: .noPadding)
        let encryptedBytes = try aes.encrypt(Array(plaintext.utf8))
        
        // Get the authentication tag (16 bytes for GCM)
        guard let tag = gcm.authenticationTag, tag.count == 16 else {
            throw LocalWalletError.keychainError("Missing GCM authentication tag")
        }
        
        // Combine IV + ciphertext + tag
        var blob = Data()
        blob.append(iv)
        blob.append(contentsOf: encryptedBytes)
        blob.append(contentsOf: tag)
        
        #if DEBUG
        #endif
        
        return (blob, salt)
    }
    
    /// Decrypt data with password
    /// Expects blob = IV (12 bytes) + ciphertext + authentication tag (16 bytes)
    private func decrypt(ciphertext: Data, salt: Data, password: String) throws -> String {
        // Minimum: 12 (IV) + 16 (tag) = 28 bytes
        guard ciphertext.count > 28 else {
            throw LocalWalletError.keychainError("Invalid ciphertext (too short)")
        }
        
        #if DEBUG
        // SECURITY: Never log password values, only metadata
        #endif
        
        // Derive key
        let key = try deriveKey(password: password, salt: salt)
        
        #if DEBUG
        #endif
        
        // Extract IV (first 12 bytes), tag (last 16 bytes), and encrypted data (middle)
        let iv = ciphertext.prefix(12)
        let tag = ciphertext.suffix(16)
        let encrypted = ciphertext.dropFirst(12).dropLast(16)
        
        #if DEBUG
        #endif
        
        // Decrypt with GCM in detached mode, providing the authentication tag
        do {
            let gcm = GCM(iv: Array(iv), authenticationTag: Array(tag), mode: .detached)
            let aes = try AES(key: Array(key), blockMode: gcm, padding: .noPadding)
            let decrypted = try aes.decrypt(Array(encrypted))
            
            #if DEBUG
            #endif
            
            guard let plaintext = String(bytes: decrypted, encoding: .utf8) else {
                #if DEBUG
                #endif
                throw LocalWalletError.keychainError("UTF-8 decode failed")
            }
            
            #if DEBUG
            // SECURITY: Don't log decrypted content (could contain mnemonics/keys)
            #endif
            
            return plaintext
        } catch let error {
            #if DEBUG
            #endif
            // Decryption failure usually means wrong password
            throw LocalWalletError.passwordIncorrect
        }
    }
    
    /// Derive encryption key from password using PBKDF2
    private func deriveKey(password: String, salt: Data) throws -> Data {
        // Use fewer iterations in DEBUG mode for faster development
        #if DEBUG
        let iterations = 1_000  // Fast for development
        #else
        let iterations = 100_000  // High iteration count for production security
        #endif
        
        let key = try PKCS5.PBKDF2(
            password: Array(password.utf8),
            salt: Array(salt),
            iterations: iterations,
            keyLength: 32,  // 256 bits
            variant: .sha2(.sha256)
        ).calculate()
        
        return Data(key)
    }
}

// MARK: - Wallet Metadata

/// Metadata about the stored wallet
struct WalletMetadata: Codable {
    let createdAt: Date
    let importMethod: WalletImportMethod
    let securityLevel: WalletSecurityLevel
    let isHDWallet: Bool
}

// MARK: - Data Hex Extension

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}
