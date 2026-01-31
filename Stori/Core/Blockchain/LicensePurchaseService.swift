//
//  LicensePurchaseService.swift
//  Stori
//
//  Wallet-based license purchase (ERC-1155)
//  Uses direct wallet signing instead of signing-service
//

import Foundation
import BigInt
import CryptoSwift

/// Service for purchasing license instances using the user's wallet
class LicensePurchaseService {
    static let shared = LicensePurchaseService()
    
    private init() {}
    
    // MARK: - Result Type
    
    struct PurchaseResult {
        let transactionHash: String
        let totalPrice: String
        let quantity: Int
    }
    
    // MARK: - Purchase License Instance
    
    /// Purchase a license instance
    /// - Parameters:
    ///   - instanceId: The ID of the license instance to purchase
    ///   - quantity: Number of licenses to purchase
    ///   - pricePerUnit: Price per license in TUS
    /// - Returns: Transaction result
    func purchaseLicenseInstance(
        instanceId: String,
        quantity: Int = 1,
        pricePerUnit: Double
    ) async throws -> PurchaseResult {
        
        let walletService = WalletService.shared
        
        // Ensure wallet is connected
        guard walletService.hasWallet, let walletAddress = walletService.address else {
            throw LicensePurchaseError.walletNotConnected
        }
        
        // Parse instanceId to Int
        guard let instanceIdInt = Int(instanceId) else {
            throw LicensePurchaseError.invalidInstanceId
        }
        
        // Calculate total price in wei (18 decimals)
        let totalPriceTUS = pricePerUnit * Double(quantity)
        let totalPriceWei = BigUInt(totalPriceTUS * 1_000_000_000_000_000_000)
        
        
        // Encode the purchaseInstance call
        let callData = encodePurchaseInstanceCall(
            instanceId: instanceIdInt,
            quantity: quantity
        )
        
        
        // Fetch nonce
        let nonce = try await walletService.fetchNonce(address: walletAddress)
        
        // Build transaction
        let contractAddress = StoriEnvironment.digitalInstanceFactoryAddress
        let chainId = BigUInt(StoriEnvironment.chainId)
        let gasPrice = BigUInt(25_000_000_000) // 25 Gwei
        let gasLimit = BigUInt(500_000) // Purchase needs more gas for royalty distribution
        
        
        let transaction = EthereumTransaction(
            nonce: nonce,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            to: contractAddress,
            value: totalPriceWei,  // This is the payment!
            data: callData,
            chainId: chainId
        )
        
        // Sign transaction
        let signedTx = try walletService.signTransaction(transaction)
        
        // Broadcast transaction
        let txHash = try await walletService.sendSignedTransaction(signedTx.rawTransaction)
        
        return PurchaseResult(
            transactionHash: txHash,
            totalPrice: String(format: "%.4f", totalPriceTUS),
            quantity: quantity
        )
    }
    
    // MARK: - ABI Encoding
    
    /// Encode purchaseInstance function call
    /// Signature: purchaseInstance(uint256 instanceId, uint256 quantity)
    private func encodePurchaseInstanceCall(
        instanceId: Int,
        quantity: Int
    ) -> Data {
        // Function selector for purchaseInstance(uint256,uint256)
        let functionSignature = "purchaseInstance(uint256,uint256)"
        let selector = functionSignature.data(using: .utf8)!.sha3(.keccak256).prefix(4)
        
        var data = Data(selector)
        
        // Encode parameters
        data.append(encodeUInt256(BigUInt(instanceId)))  // instanceId
        data.append(encodeUInt256(BigUInt(quantity)))    // quantity
        
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

enum LicensePurchaseError: LocalizedError {
    case walletNotConnected
    case invalidInstanceId
    case insufficientBalance
    case transactionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .walletNotConnected:
            return "Please connect your wallet first"
        case .invalidInstanceId:
            return "Invalid license instance ID"
        case .insufficientBalance:
            return "Insufficient TUS balance"
        case .transactionFailed(let message):
            return "Transaction failed: \(message)"
        }
    }
}
