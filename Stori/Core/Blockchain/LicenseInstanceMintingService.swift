//
//  LicenseInstanceMintingService.swift
//  Stori
//
//  Wallet-based license instance creation (ERC-1155)
//  Replaces the old signing-service flow
//

import Foundation
import BigInt
import Combine
import CryptoSwift

/// Service for creating license instances using the user's wallet
class LicenseInstanceMintingService {
    static let shared = LicenseInstanceMintingService()
    
    private init() {}
    
    // MARK: - License Type Enum (matches contract)
    
    enum ContractLicenseType: Int {
        case fullOwnership = 0
        case streaming = 1
        case limitedPlay = 2
        case timeLimited = 3
        case commercialLicense = 4
    }
    
    // MARK: - Result Type
    
    struct LicenseCreationResult {
        let transactionHash: String
        let instanceId: String? // Will be determined after indexing
    }
    
    // MARK: - Create License Instance
    
    /// Create a new license instance for a Digital Master
    /// - Parameters:
    ///   - masterId: The Digital Master token ID
    ///   - licenseType: Type of license to create
    ///   - price: Price in TUS (will be converted to wei)
    ///   - maxSupply: Maximum number that can be minted (0 = unlimited)
    ///   - playsPerInstance: Number of plays included (for limited play licenses)
    ///   - durationInDays: Duration in days (for time-limited licenses)
    ///   - isTransferable: Whether the license can be transferred
    /// - Returns: Transaction result
    func createLicenseInstance(
        masterId: Int,
        licenseType: ContractLicenseType,
        price: Double,
        maxSupply: Int,
        playsPerInstance: Int,
        durationInDays: Int,
        isTransferable: Bool
    ) async throws -> LicenseCreationResult {
        
        let walletService = WalletService.shared
        
        // Ensure wallet is connected
        guard walletService.hasWallet, let walletAddress = walletService.address else {
            throw LicenseCreationError.walletNotConnected
        }
        
        
        // Convert price to wei (18 decimals)
        let priceWei = BigUInt(price * 1_000_000_000_000_000_000)
        
        // Encode the createInstance call
        let callData = encodeCreateInstanceCall(
            masterId: masterId,
            licenseType: licenseType.rawValue,
            price: priceWei,
            maxSupply: maxSupply,
            playsPerInstance: playsPerInstance,
            durationInDays: durationInDays,
            isTransferable: isTransferable
        )
        
        
        // Fetch nonce
        let nonce = try await walletService.fetchNonce(address: walletAddress)
        
        // Build transaction
        let contractAddress = StoriEnvironment.digitalInstanceFactoryAddress
        let chainId = BigUInt(StoriEnvironment.chainId)
        let gasPrice = BigUInt(25_000_000_000) // 25 Gwei
        let gasLimit = BigUInt(300_000) // License creation uses less gas
        
        
        let transaction = EthereumTransaction(
            nonce: nonce,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            to: contractAddress,
            value: BigUInt(0),
            data: callData,
            chainId: chainId
        )
        
        // Sign transaction
        let signedTx = try walletService.signTransaction(transaction)
        
        // Broadcast transaction
        let txHash = try await walletService.sendSignedTransaction(signedTx.rawTransaction)
        
        return LicenseCreationResult(
            transactionHash: txHash,
            instanceId: nil // Will be indexed later
        )
    }
    
    // MARK: - ABI Encoding
    
    /// Encode createInstance function call
    /// Full signature: createInstance(uint256,uint8,uint256,uint256,uint256,uint256,bool,string,string)
    private func encodeCreateInstanceCall(
        masterId: Int,
        licenseType: Int,
        price: BigUInt,
        maxSupply: Int,
        playsPerInstance: Int,
        durationInDays: Int,
        isTransferable: Bool
    ) -> Data {
        // Function selector for full 9-parameter signature
        let functionSignature = "createInstance(uint256,uint8,uint256,uint256,uint256,uint256,bool,string,string)"
        let selector = functionSignature.data(using: .utf8)!.sha3(.keccak256).prefix(4)
        
        var data = Data(selector)
        
        // ABI encoding for mixed static/dynamic types:
        // - First, all 9 "head" values (static values or offsets for dynamic)
        // - Then, the actual dynamic data (string contents)
        
        // Head section (9 slots × 32 bytes = 288 bytes)
        data.append(encodeUInt256(BigUInt(masterId)))               // slot 0: masterId
        data.append(encodeUInt256(BigUInt(licenseType)))            // slot 1: licenseType (uint8 padded)
        data.append(encodeUInt256(price))                           // slot 2: price
        data.append(encodeUInt256(BigUInt(maxSupply)))              // slot 3: maxSupply
        data.append(encodeUInt256(BigUInt(playsPerInstance)))       // slot 4: playsPerInstance
        data.append(encodeUInt256(BigUInt(durationInDays)))         // slot 5: durationInDays
        data.append(encodeUInt256(BigUInt(isTransferable ? 1 : 0))) // slot 6: isTransferable
        
        // Offsets to dynamic data (relative to start of encoding, after selector)
        // String 1 starts at byte 288 (after 9 head slots)
        data.append(encodeUInt256(BigUInt(9 * 32)))                 // slot 7: offset to metadataURI = 288
        // String 2 starts at byte 320 (after string1's length field)
        data.append(encodeUInt256(BigUInt(10 * 32)))                // slot 8: offset to encryptedContentURI = 320
        
        // Dynamic data section
        // String 1 (metadataURI) - empty string: just length = 0
        data.append(encodeUInt256(BigUInt(0)))                      // metadataURI length = 0
        
        // String 2 (encryptedContentURI) - empty string: just length = 0
        data.append(encodeUInt256(BigUInt(0)))                      // encryptedContentURI length = 0
        
        
        return data
    }
    
    /// Encode a BigUInt as 32-byte padded value
    private func encodeUInt256(_ value: BigUInt) -> Data {
        let bytes = Array(value.serialize())
        if bytes.count >= 32 {
            return Data(bytes.suffix(32))
        }
        return Data(repeating: 0, count: 32 - bytes.count) + Data(bytes)
    }
}

// MARK: - Errors

enum LicenseCreationError: LocalizedError {
    case walletNotConnected
    case transactionFailed(String)
    case encodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .walletNotConnected:
            return "Please connect your wallet first"
        case .transactionFailed(let message):
            return "Transaction failed: \(message)"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        }
    }
}
