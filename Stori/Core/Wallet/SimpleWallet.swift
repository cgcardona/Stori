//
//  SimpleWallet.swift
//  Stori
//
//  Single private key wallet for development/testing
//  Uses Web3.swift (Boilertalk) for all crypto operations - NO CUSTOM CRYPTO
//

import Foundation
import CryptoSwift
import Web3

// MARK: - Simple Wallet

/// A wallet backed by a single private key (no HD derivation)
/// Primarily used for imported private keys and development/testing
final class SimpleWallet: WalletProtocol {
    
    // MARK: - Properties
    
    /// The Ethereum address derived from this private key
    let address: String
    
    /// Indicates this is NOT an HD wallet
    let isHDWallet = false
    
    /// How this wallet was imported
    let importMethod: WalletImportMethod = .privateKey
    
    // SECURITY: Dev key detection removed - no hardcoded keys in codebase
    
    /// The private key data (stored securely)
    private let privateKeyData: Data
    
    /// The Web3.swift private key for signing
    private let ethereumPrivateKey: EthereumPrivateKey
    
    // MARK: - Initialization
    
    /// Initialize from a hex private key string
    /// - Parameter hexKey: Private key as hex string (with or without 0x prefix)
    convenience init(hexKey: String) throws {
        let keyData = try PrivateKeyParser.parse(hexKey)
        try self.init(privateKey: keyData)
    }
    
    /// Initialize from raw private key data
    /// - Parameter privateKey: 32-byte private key
    init(privateKey: Data) throws {
        guard privateKey.count == 32 else {
            throw LocalWalletError.invalidPrivateKey("Private key must be 32 bytes")
        }
        
        self.privateKeyData = privateKey
        
        // Create Web3.swift private key
        do {
            self.ethereumPrivateKey = try EthereumPrivateKey(privateKey: Array(privateKey))
            self.address = ethereumPrivateKey.address.hex(eip55: true)
        } catch {
            throw LocalWalletError.invalidPrivateKey("Failed to create key: \(error.localizedDescription)")
        }
    }
    
    // MARK: - WalletProtocol
    
    /// Sign a message hash (32 bytes)
    func signHash(_ hash: Data) throws -> Data {
        guard hash.count == 32 else {
            throw LocalWalletError.signingFailed("Message hash must be 32 bytes")
        }
        
        do {
            // IMPORTANT: Use sign(hash:) NOT sign(message:)!
            // sign(message:) hashes the input again, but we already have a hash
            let signature = try ethereumPrivateKey.sign(hash: Array(hash))
            
            
            // Normalize v to recovery id (0 or 1)
            // Web3.swift may return 27/28 (pre-EIP-155) or 0/1
            var recoveryId = signature.v
            if recoveryId >= 27 {
                recoveryId = recoveryId - 27
            }
            
            
            // Combine into 65 bytes: r (32) + s (32) + v (1)
            var result = Data(signature.r)
            result.append(contentsOf: signature.s)
            result.append(UInt8(recoveryId))
            
            return result
        } catch {
            throw LocalWalletError.signingFailed(error.localizedDescription)
        }
    }
    
    /// Get the private key data
    func getPrivateKey() throws -> Data {
        return privateKeyData
    }
}

// MARK: - Private Key Parser

/// Parses and validates private key strings
enum PrivateKeyParser {
    
    /// Supported private key formats
    enum Format {
        case hex           // 64 hex characters (32 bytes)
        case hexPrefixed   // With 0x prefix
    }
    
    /// Parse a private key string into Data
    /// - Parameter input: Private key as hex string
    /// - Returns: 32-byte private key data
    static func parse(_ input: String) throws -> Data {
        var cleanInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove 0x prefix if present
        if cleanInput.hasPrefix("0x") || cleanInput.hasPrefix("0X") {
            cleanInput = String(cleanInput.dropFirst(2))
        }
        
        // Validate length
        guard cleanInput.count == 64 else {
            throw LocalWalletError.invalidPrivateKey("Must be 64 hex characters (got \(cleanInput.count))")
        }
        
        // Validate hex characters
        guard cleanInput.allSatisfy({ $0.isHexDigit }) else {
            throw LocalWalletError.invalidPrivateKey("Contains invalid characters (only 0-9, a-f allowed)")
        }
        
        // Convert to Data
        guard let data = Data(hexString: cleanInput) else {
            throw LocalWalletError.invalidPrivateKey("Failed to parse hex string")
        }
        
        // Validate by trying to create a private key (Web3.swift will validate)
        do {
            _ = try EthereumPrivateKey(privateKey: Array(data))
        } catch {
            throw LocalWalletError.invalidPrivateKey("Not a valid secp256k1 private key")
        }
        
        return data
    }
    
    /// Validate a private key string without throwing
    static func isValid(_ input: String) -> Bool {
        do {
            _ = try parse(input)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Array<UInt8> to Data

private extension Array where Element == UInt8 {
    var data: Data {
        return Data(self)
    }
}
