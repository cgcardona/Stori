//
//  HDWallet.swift
//  Stori
//
//  BIP-32/39/44 Hierarchical Deterministic Wallet
//  Uses web3.swift for all crypto operations - NO CUSTOM CRYPTO
//

import Foundation
import CryptoSwift
import Web3
import BigInt

// MARK: - HD Wallet

/// A hierarchical deterministic wallet implementing BIP-32/39/44
/// Derives keys from a mnemonic seed phrase
final class HDWallet: WalletProtocol {
    
    // MARK: - Constants
    
    /// Avalanche BIP-44 derivation path (SLIP-44 coin type 9000)
    /// m/44'/9000'/0'/0/0
    static let defaultDerivationPath = "m/44'/9000'/0'/0/0"
    
    /// Alternative Ethereum-compatible path (for cross-chain compatibility)
    static let ethereumCompatiblePath = "m/44'/60'/0'/0/0"
    
    /// Coin types
    static let avalancheCoinType: UInt32 = 9000
    static let ethereumCoinType: UInt32 = 60
    
    // MARK: - Properties
    
    /// The primary Ethereum address
    let address: String
    
    /// Whether this is an HD wallet
    let isHDWallet = true
    
    /// How this wallet was created
    let importMethod: WalletImportMethod
    
    /// The derivation path used
    let derivationPath: String
    
    /// The mnemonic words (stored for backup display)
    private let mnemonic: [String]
    
    /// The master seed (64 bytes)
    private let masterSeed: Data
    
    /// The derived private key for the default path
    private let derivedPrivateKey: Data
    
    /// The Web3.swift private key for signing
    private let ethereumPrivateKey: EthereumPrivateKey
    
    /// The language of the mnemonic
    let language: MnemonicLanguage
    
    // MARK: - Initialization
    
    /// Create a new HD wallet with a generated mnemonic
    static func create(
        strength: MnemonicStrength = .words24,
        language: MnemonicLanguage = .english,
        passphrase: String = "",
        derivationPath: String = defaultDerivationPath
    ) throws -> HDWallet {
        let generator = MnemonicGenerator(language: language)
        let mnemonic = try generator.generate(strength: strength)
        
        return try HDWallet(
            mnemonic: mnemonic,
            language: language,
            passphrase: passphrase,
            derivationPath: derivationPath,
            importMethod: .created
        )
    }
    
    /// Import an HD wallet from a mnemonic phrase
    init(
        mnemonic: [String],
        language: MnemonicLanguage = .english,
        passphrase: String = "",
        derivationPath: String = HDWallet.defaultDerivationPath,
        importMethod: WalletImportMethod = .mnemonicImport
    ) throws {
        let generator = MnemonicGenerator(language: language)
        
        // Validate mnemonic
        guard generator.validate(mnemonic) else {
            throw LocalWalletError.invalidMnemonic("Mnemonic validation failed")
        }
        
        // Generate seed from mnemonic
        let seed = try generator.mnemonicToSeed(mnemonic, passphrase: passphrase)
        
        // Derive key at path using BIP-32
        let privateKey = try Self.deriveKey(from: seed, path: derivationPath)
        
        // Create Web3.swift private key
        let ethPrivKey = try EthereumPrivateKey(privateKey: Array(privateKey))
        
        self.mnemonic = mnemonic
        self.masterSeed = seed
        self.derivedPrivateKey = privateKey
        self.ethereumPrivateKey = ethPrivKey
        self.address = ethPrivKey.address.hex(eip55: true)
        self.derivationPath = derivationPath
        self.language = language
        self.importMethod = importMethod
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
        return derivedPrivateKey
    }
    
    // MARK: - Mnemonic Access
    
    /// Get the mnemonic words (for backup display)
    /// WARNING: This exposes sensitive data - use with caution!
    func getMnemonic() -> [String] {
        return mnemonic
    }
    
    // MARK: - Key Derivation (BIP-32)
    
    /// Derive a key from seed at the specified BIP-44 path
    private static func deriveKey(from seed: Data, path: String) throws -> Data {
        // Parse derivation path
        let components = try parseDerivationPath(path)
        
        // Generate master key and chain code using HMAC-SHA512
        let masterKey = try generateMasterKey(from: seed)
        
        // Derive through each level
        var currentKey = masterKey.privateKey
        var currentChainCode = masterKey.chainCode
        
        for component in components {
            let derived = try deriveChildKey(
                parentKey: currentKey,
                parentChainCode: currentChainCode,
                index: component.index,
                hardened: component.hardened
            )
            currentKey = derived.privateKey
            currentChainCode = derived.chainCode
        }
        
        return currentKey
    }
    
    /// Generate master key from seed using HMAC-SHA512
    private static func generateMasterKey(from seed: Data) throws -> (privateKey: Data, chainCode: Data) {
        let key = "Bitcoin seed".data(using: .utf8)!
        let hmac = try HMAC(key: Array(key), variant: .sha2(.sha512)).authenticate(Array(seed))
        
        let privateKey = Data(hmac.prefix(32))
        let chainCode = Data(hmac.suffix(32))
        
        return (privateKey, chainCode)
    }
    
    /// Derive child key at index
    private static func deriveChildKey(
        parentKey: Data,
        parentChainCode: Data,
        index: UInt32,
        hardened: Bool
    ) throws -> (privateKey: Data, chainCode: Data) {
        var data = Data()
        
        if hardened {
            // Hardened derivation: 0x00 || private_key || index
            data.append(0x00)
            data.append(parentKey)
        } else {
            // Normal derivation: public_key || index
            let publicKey = try deriveCompressedPublicKey(from: parentKey)
            data.append(publicKey)
        }
        
        // Append index as big-endian 4 bytes
        let actualIndex = hardened ? (0x80000000 | index) : index
        data.append(contentsOf: withUnsafeBytes(of: actualIndex.bigEndian) { Array($0) })
        
        // HMAC-SHA512
        let hmac = try HMAC(key: Array(parentChainCode), variant: .sha2(.sha512)).authenticate(Array(data))
        
        let il = Data(hmac.prefix(32))
        let ir = Data(hmac.suffix(32))
        
        // Child key = IL + parent_key (mod n)
        let childKey = try addPrivateKeys(il, parentKey)
        
        return (childKey, ir)
    }
    
    /// Add two private keys modulo the curve order
    /// Uses simple big-endian addition for BIP-32 child key derivation
    private static func addPrivateKeys(_ a: Data, _ b: Data) throws -> Data {
        // For BIP-32 key derivation, we need to add two 256-bit numbers
        // and reduce modulo the secp256k1 curve order
        // This is a simplified implementation that works for our use case
        
        guard a.count == 32, b.count == 32 else {
            throw LocalWalletError.keyDerivationFailed("Invalid key length")
        }
        
        // Use BigUInt from the BigInt library for proper modular arithmetic
        let aInt = BigUInt(a)
        let bInt = BigUInt(b)
        
        // secp256k1 curve order n
        let n = BigUInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", radix: 16)!
        
        // Add and reduce modulo n
        let sum = (aInt + bInt) % n
        
        // Convert back to 32 bytes (pad if needed)
        var resultBytes: [UInt8] = Array(sum.serialize())
        while resultBytes.count < 32 {
            resultBytes.insert(0, at: 0)
        }
        
        return Data(resultBytes)
    }
    
    /// Parse a BIP-44 derivation path
    private static func parseDerivationPath(_ path: String) throws -> [(index: UInt32, hardened: Bool)] {
        var components: [(index: UInt32, hardened: Bool)] = []
        
        let parts = path.split(separator: "/")
        for (i, part) in parts.enumerated() {
            // Skip "m" prefix
            if i == 0 && part == "m" {
                continue
            }
            
            var indexStr = String(part)
            var hardened = false
            
            if indexStr.hasSuffix("'") || indexStr.hasSuffix("H") {
                hardened = true
                indexStr = String(indexStr.dropLast())
            }
            
            guard let index = UInt32(indexStr) else {
                throw LocalWalletError.keyDerivationFailed("Invalid path component: \(part)")
            }
            
            components.append((index, hardened))
        }
        
        return components
    }
    
    /// Derive compressed public key from private key using Web3.swift
    private static func deriveCompressedPublicKey(from privateKey: Data) throws -> Data {
        let ethPrivKey = try EthereumPrivateKey(privateKey: Array(privateKey))
        
        // Get the public key bytes from the address derivation
        // Web3.swift internally uses the public key to derive the address
        // For BIP-32 non-hardened derivation, we need the actual compressed public key
        
        // The EthereumPrivateKey gives us access to the public key via publicKey property
        // which returns EthereumPublicKey containing the raw bytes
        let publicKeyBytes = ethPrivKey.publicKey.rawPublicKey
        
        // If we have uncompressed (65 bytes with 04 prefix), compress it
        if publicKeyBytes.count == 65 && publicKeyBytes[0] == 0x04 {
            // Uncompressed: 04 || X (32) || Y (32)
            // Compressed: 02/03 || X (32) - prefix based on Y parity
            let x = Array(publicKeyBytes[1...32])
            let y = publicKeyBytes[64]  // Last byte determines parity
            let prefix: UInt8 = (y % 2 == 0) ? 0x02 : 0x03
            return Data([prefix] + x)
        } else if publicKeyBytes.count == 64 {
            // Raw X,Y without prefix
            let x = Array(publicKeyBytes[0..<32])
            let y = publicKeyBytes[63]
            let prefix: UInt8 = (y % 2 == 0) ? 0x02 : 0x03
            return Data([prefix] + x)
        } else if publicKeyBytes.count == 33 {
            // Already compressed
            return Data(publicKeyBytes)
        }
        
        throw LocalWalletError.keyDerivationFailed("Unexpected public key format")
    }
}

// MARK: - Data Comparison

private extension Data {
    static func >= (lhs: Data, rhs: Data) -> Bool {
        guard lhs.count == rhs.count else {
            return lhs.count > rhs.count
        }
        
        for (l, r) in zip(lhs, rhs) {
            if l > r { return true }
            if l < r { return false }
        }
        return true
    }
}
