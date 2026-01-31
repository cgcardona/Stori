//
//  TransactionSigner.swift
//  Stori
//
//  EIP-155 transaction signing and EIP-712 typed data signing
//

import Foundation
import CryptoSwift
import BigInt
import Web3

// MARK: - Transaction Types

/// Raw Ethereum transaction data
struct EthereumTransaction {
    let nonce: BigUInt
    let gasPrice: BigUInt
    let gasLimit: BigUInt
    let to: String?  // nil for contract creation
    let value: BigUInt
    let data: Data
    let chainId: BigUInt
    
    /// Create a simple TUS transfer transaction
    static func transfer(
        to: String,
        value: BigUInt,
        nonce: BigUInt,
        gasPrice: BigUInt = BigUInt(25_000_000_000),  // 25 Gwei default
        gasLimit: BigUInt = BigUInt(21_000),
        chainId: BigUInt
    ) -> EthereumTransaction {
        return EthereumTransaction(
            nonce: nonce,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            to: to,
            value: value,
            data: Data(),
            chainId: chainId
        )
    }
    
    /// Create a contract call transaction
    static func contractCall(
        to: String,
        data: Data,
        nonce: BigUInt,
        value: BigUInt = 0,
        gasPrice: BigUInt = BigUInt(25_000_000_000),
        gasLimit: BigUInt = BigUInt(100_000),
        chainId: BigUInt
    ) -> EthereumTransaction {
        return EthereumTransaction(
            nonce: nonce,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            to: to,
            value: value,
            data: data,
            chainId: chainId
        )
    }
}

/// EIP-1559 transaction (Type 2)
struct EIP1559Transaction {
    let chainId: BigUInt
    let nonce: BigUInt
    let maxPriorityFeePerGas: BigUInt
    let maxFeePerGas: BigUInt
    let gasLimit: BigUInt
    let to: String?
    let value: BigUInt
    let data: Data
    let accessList: [(address: String, storageKeys: [Data])]
    
    /// Create a simple transfer with EIP-1559
    static func transfer(
        to: String,
        value: BigUInt,
        nonce: BigUInt,
        maxPriorityFeePerGas: BigUInt = BigUInt(1_500_000_000),  // 1.5 Gwei
        maxFeePerGas: BigUInt = BigUInt(30_000_000_000),  // 30 Gwei
        gasLimit: BigUInt = BigUInt(21_000),
        chainId: BigUInt
    ) -> EIP1559Transaction {
        return EIP1559Transaction(
            chainId: chainId,
            nonce: nonce,
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            maxFeePerGas: maxFeePerGas,
            gasLimit: gasLimit,
            to: to,
            value: value,
            data: Data(),
            accessList: []
        )
    }
}

/// Signed transaction ready to broadcast
struct SignedTransaction {
    let rawTransaction: Data
    let transactionHash: Data
    let v: BigUInt
    let r: Data
    let s: Data
    
    /// Hex-encoded raw transaction for RPC submission
    var rawTransactionHex: String {
        "0x" + rawTransaction.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Transaction hash as hex string
    var transactionHashHex: String {
        "0x" + transactionHash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - EIP-712 Typed Data

/// EIP-712 domain separator
struct EIP712Domain: Codable {
    let name: String
    let version: String
    let chainId: UInt64
    let verifyingContract: String
    
    var typeHash: Data {
        let typeString = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        return keccak256(Array(typeString.utf8))
    }
    
    func hash() throws -> Foundation.Data {
        var encoded = Foundation.Data()
        encoded.append(contentsOf: typeHash)
        encoded.append(contentsOf: keccak256(Array(name.utf8)))
        encoded.append(contentsOf: keccak256(Array(version.utf8)))
        let chainIdBI = BigUInt(exactly: chainId) ?? BigUInt(0)
        encoded.append(contentsOf: chainIdBI.abiEncode())
        encoded.append(contentsOf: try addressToBytes32(verifyingContract))
        return keccak256(Array(encoded))
    }
}

/// Generic EIP-712 typed data structure
struct EIP712TypedData {
    let domain: EIP712Domain
    let primaryType: String
    let types: [String: [(name: String, type: String)]]
    let message: [String: Any]
    
    /// Compute the struct hash for the message
    func messageHash() throws -> Data {
        guard let typeFields = types[primaryType] else {
            throw LocalWalletError.signingFailed("Unknown type: \(primaryType)")
        }
        
        // Build type string
        let typeString = "\(primaryType)(" + typeFields.map { "\($0.type) \($0.name)" }.joined(separator: ",") + ")"
        let typeHash = keccak256(Array(typeString.utf8))
        
        // Encode message
        var encoded = Data()
        encoded.append(contentsOf: typeHash)
        
        for field in typeFields {
            if let value = message[field.name] {
                let encodedValue = try encodeValue(value, type: field.type)
                encoded.append(contentsOf: encodedValue)
            }
        }
        
        return keccak256(Array(encoded))
    }
    
    /// Compute the final signing hash (EIP-712 format)
    func signingHash() throws -> Data {
        let domainHash = try domain.hash()
        let structHash = try messageHash()
        
        var data = Data([0x19, 0x01])
        data.append(contentsOf: domainHash)
        data.append(contentsOf: structHash)
        
        return keccak256(Array(data))
    }
    
    private func encodeValue(_ value: Any, type: String) throws -> Data {
        switch type {
        case "string":
            guard let str = value as? String else {
                throw LocalWalletError.signingFailed("Expected string")
            }
            return keccak256(Array(str.utf8))
            
        case "bytes":
            guard let bytes = value as? Data else {
                throw LocalWalletError.signingFailed("Expected bytes")
            }
            return keccak256(Array(bytes))
            
        case "bytes32":
            guard let bytes = value as? Data, bytes.count == 32 else {
                throw LocalWalletError.signingFailed("Expected bytes32")
            }
            return bytes
            
        case "address":
            guard let addr = value as? String else {
                throw LocalWalletError.signingFailed("Expected address")
            }
            return try addressToBytes32(addr)
            
        case "uint256":
            if let bigInt = value as? BigUInt {
                return bigInt.abiEncode()
            } else if let uint = value as? UInt64 {
                let bi = BigUInt(exactly: uint) ?? BigUInt(0)
                return bi.abiEncode()
            } else if let int = value as? Int {
                let bi = BigUInt(exactly: int) ?? BigUInt(0)
                return bi.abiEncode()
            }
            throw LocalWalletError.signingFailed("Expected uint256")
            
        case "bool":
            guard let bool = value as? Bool else {
                throw LocalWalletError.signingFailed("Expected bool")
            }
            return BigUInt(bool ? 1 : 0).abiEncode()
            
        default:
            throw LocalWalletError.signingFailed("Unsupported type: \(type)")
        }
    }
}

// MARK: - Transaction Signer

/// Handles EIP-155 and EIP-712 signing
class TransactionSigner {
    
    private let wallet: WalletProtocol
    
    init(wallet: WalletProtocol) {
        self.wallet = wallet
    }
    
    // MARK: - EIP-155 Transaction Signing
    
    /// Sign a legacy transaction with EIP-155 replay protection
    /// - Parameter transaction: The transaction to sign
    /// - Returns: Signed transaction ready for broadcast
    func signTransaction(_ transaction: EthereumTransaction) throws -> SignedTransaction {
        // RLP encode for signing (includes chainId for EIP-155)
        let signingData = try rlpEncodeForSigning(transaction)
        let signingHash = keccak256(Array(signingData))
        
        
        // Sign the hash
        let signature = try wallet.signHash(signingHash)
        
        guard signature.count == 65 else {
            throw LocalWalletError.signingFailed("Invalid signature length")
        }
        
        let signatureBytes = Array(signature)
        let r = Foundation.Data(signatureBytes[0..<32])
        let s = Foundation.Data(signatureBytes[32..<64])
        let recoveryId = signatureBytes[64]
        
        // EIP-155: v = chainId * 2 + 35 + recoveryId
        let recoveryBigUInt = BigUInt(exactly: recoveryId) ?? BigUInt(0)
        let v = transaction.chainId * 2 + 35 + recoveryBigUInt
        
        // RLP encode the signed transaction
        let signedData = try rlpEncodeSigned(transaction, v: v, r: r, s: s)
        let txHash = keccak256(Array(signedData))
        
        return SignedTransaction(
            rawTransaction: signedData,
            transactionHash: txHash,
            v: v,
            r: r,
            s: s
        )
    }
    
    /// Sign an EIP-1559 transaction
    func signEIP1559Transaction(_ transaction: EIP1559Transaction) throws -> SignedTransaction {
        // RLP encode for signing (Type 2 transaction)
        let signingData = try rlpEncodeEIP1559ForSigning(transaction)
        
        // Prefix with transaction type (0x02)
        var prefixedData = Data([0x02])
        prefixedData.append(signingData)
        
        let signingHash = keccak256(Array(prefixedData))
        
        // Sign the hash
        let signature = try wallet.signHash(signingHash)
        
        guard signature.count == 65 else {
            throw LocalWalletError.signingFailed("Invalid signature length")
        }
        
        let signatureBytes = Array(signature)
        let r = Foundation.Data(signatureBytes[0..<32])
        let s = Foundation.Data(signatureBytes[32..<64])
        let recoveryId = signatureBytes[64]
        
        // For EIP-1559, v is just the recovery id (0 or 1)
        let v = BigUInt(exactly: recoveryId) ?? BigUInt(0)
        
        // RLP encode the signed transaction
        let signedPayload = try rlpEncodeEIP1559Signed(transaction, v: v, r: r, s: s)
        
        // Prefix with transaction type
        var signedData = Data([0x02])
        signedData.append(signedPayload)
        
        let txHash = keccak256(Array(signedData))
        
        return SignedTransaction(
            rawTransaction: signedData,
            transactionHash: txHash,
            v: v,
            r: r,
            s: s
        )
    }
    
    // MARK: - EIP-712 Typed Data Signing
    
    /// Sign EIP-712 typed structured data
    /// - Parameter typedData: The typed data to sign
    /// - Returns: 65-byte signature (r + s + v)
    func signTypedData(_ typedData: EIP712TypedData) throws -> Data {
        let hash = try typedData.signingHash()
        return try wallet.signHash(hash)
    }
    
    /// Sign a permit (ERC-2612 style)
    func signPermit(
        owner: String,
        spender: String,
        value: BigUInt,
        nonce: BigUInt,
        deadline: UInt64,
        tokenName: String,
        tokenAddress: String,
        chainId: UInt64
    ) throws -> Data {
        let domain = EIP712Domain(
            name: tokenName,
            version: "1",
            chainId: chainId,
            verifyingContract: tokenAddress
        )
        
        let typedData = EIP712TypedData(
            domain: domain,
            primaryType: "Permit",
            types: [
                "Permit": [
                    (name: "owner", type: "address"),
                    (name: "spender", type: "address"),
                    (name: "value", type: "uint256"),
                    (name: "nonce", type: "uint256"),
                    (name: "deadline", type: "uint256")
                ]
            ],
            message: [
                "owner": owner,
                "spender": spender,
                "value": value,
                "nonce": nonce,
                "deadline": deadline
            ]
        )
        
        return try signTypedData(typedData)
    }
    
    // MARK: - RLP Encoding
    
    private func rlpEncodeForSigning(_ tx: EthereumTransaction) throws -> Data {
        let items: [Any] = [
            tx.nonce,
            tx.gasPrice,
            tx.gasLimit,
            tx.to != nil ? try addressToData(tx.to!) : Data(),
            tx.value,
            tx.data,
            tx.chainId,
            BigUInt(0),  // Empty r for EIP-155
            BigUInt(0)   // Empty s for EIP-155
        ]
        return try rlpEncode(items)
    }
    
    private func rlpEncodeSigned(_ tx: EthereumTransaction, v: BigUInt, r: Data, s: Data) throws -> Data {
        let items: [Any] = [
            tx.nonce,
            tx.gasPrice,
            tx.gasLimit,
            tx.to != nil ? try addressToData(tx.to!) : Data(),
            tx.value,
            tx.data,
            v,
            r,
            s
        ]
        return try rlpEncode(items)
    }
    
    private func rlpEncodeEIP1559ForSigning(_ tx: EIP1559Transaction) throws -> Data {
        let items: [Any] = [
            tx.chainId,
            tx.nonce,
            tx.maxPriorityFeePerGas,
            tx.maxFeePerGas,
            tx.gasLimit,
            tx.to != nil ? try addressToData(tx.to!) : Data(),
            tx.value,
            tx.data,
            [] as [Any]  // Empty access list
        ]
        return try rlpEncode(items)
    }
    
    private func rlpEncodeEIP1559Signed(_ tx: EIP1559Transaction, v: BigUInt, r: Data, s: Data) throws -> Data {
        let items: [Any] = [
            tx.chainId,
            tx.nonce,
            tx.maxPriorityFeePerGas,
            tx.maxFeePerGas,
            tx.gasLimit,
            tx.to != nil ? try addressToData(tx.to!) : Data(),
            tx.value,
            tx.data,
            [] as [Any],  // Access list
            v,
            r,
            s
        ]
        return try rlpEncode(items)
    }
    
    // MARK: - RLP Encoding Helpers
    
    private func rlpEncode(_ items: [Any]) throws -> Data {
        var encoded = Data()
        for item in items {
            encoded.append(try rlpEncodeItem(item))
        }
        return rlpEncodeLength(encoded.count, offset: 0xc0) + encoded
    }
    
    private func rlpEncodeItem(_ item: Any) throws -> Data {
        if let bigInt = item as? BigUInt {
            if bigInt == 0 {
                return Data([0x80])
            }
            let bytes = bigInt.serialize()
            if bytes.count == 1 && bytes[0] < 0x80 {
                return bytes
            }
            return rlpEncodeLength(bytes.count, offset: 0x80) + bytes
        } else if let data = item as? Data {
            if data.count == 0 {
                return Data([0x80])
            }
            if data.count == 1 && data[0] < 0x80 {
                return data
            }
            return rlpEncodeLength(data.count, offset: 0x80) + data
        } else if let array = item as? [Any] {
            var encoded = Data()
            for element in array {
                encoded.append(try rlpEncodeItem(element))
            }
            return rlpEncodeLength(encoded.count, offset: 0xc0) + encoded
        } else {
            throw LocalWalletError.signingFailed("Unsupported RLP type")
        }
    }
    
    private func rlpEncodeLength(_ length: Int, offset: UInt8) -> Data {
        if length < 56 {
            return Data([offset + UInt8(length)])
        } else {
            let lengthBytes = encodeLength(length)
            return Data([offset + 55 + UInt8(lengthBytes.count)]) + lengthBytes
        }
    }
    
    private func encodeLength(_ length: Int) -> Data {
        var len = length
        var result = Data()
        while len > 0 {
            result.insert(UInt8(len & 0xff), at: 0)
            len >>= 8
        }
        return result
    }
    
    private func addressToData(_ address: String) throws -> Data {
        var hex = address
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        guard hex.count == 40,
              let data = Data(hexString: hex),
              data.count == 20 else {
            throw LocalWalletError.invalidAddress("Invalid address: \(address)")
        }
        return data
    }
}

// MARK: - Helper Functions

/// Keccak256 hash returning Data
private func keccak256(_ bytes: [UInt8]) -> Data {
    return Data(bytes.sha3(.keccak256))
}

/// Convert address to 32-byte padded form
private func addressToBytes32(_ address: String) throws -> Data {
    var hex = address
    if hex.hasPrefix("0x") {
        hex = String(hex.dropFirst(2))
    }
    guard hex.count == 40,
          let data = Data(hexString: hex) else {
        throw LocalWalletError.invalidAddress("Invalid address")
    }
    // Pad to 32 bytes for ABI encoding
    return Data(repeating: 0, count: 12) + data
}

// MARK: - Extensions

extension BigUInt {
    /// ABI encode as 32-byte value
    func abiEncode() -> Foundation.Data {
        let bytes = Array(self.serialize())
        if bytes.count >= 32 {
            return Foundation.Data(bytes.suffix(32))
        }
        return Foundation.Data(repeating: 0, count: 32 - bytes.count) + Foundation.Data(bytes)
    }
}

// Note: Data.init(hexString:) is defined in WalletTypes.swift or HDWallet.swift
