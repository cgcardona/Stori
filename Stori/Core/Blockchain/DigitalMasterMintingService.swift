//
//  DigitalMasterMintingService.swift
//  Stori
//
//  Wallet-based Digital Master minting service
//  Replaces the signing-service with direct wallet transactions
//

import Foundation
import BigInt
import CryptoSwift
import Combine
import Observation

// MARK: - IPFS Upload Service

class IPFSUploadService {
    static let shared = IPFSUploadService()
    
    // Direct IPFS daemon API (more reliable than going through indexer)
    private let ipfsAPIURL = "http://127.0.0.1:5001"
    private let ipfsGatewayURL: String
    
    init() {
        self.ipfsGatewayURL = StoriEnvironment.ipfsGatewayURL
    }
    
    /// Upload binary data directly to IPFS daemon
    func uploadData(_ data: Data, filename: String) async throws -> MintingIPFSResult {
        guard let url = URL(string: "\(ipfsAPIURL)/api/v0/add?pin=true") else {
            throw IPFSError.invalidURL
        }
        
        // Create multipart form data for IPFS API
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300 // 5 minutes for large files
        
        var body = Data()
        
        // Add file part (IPFS expects "file" as the form field name)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseText = String(data: responseData, encoding: .utf8) ?? "Unknown"
            throw IPFSError.uploadFailed("HTTP \(statusCode): \(responseText)")
        }
        
        // IPFS returns JSON with "Hash" field
        let result = try JSONDecoder().decode(IPFSAddResponse.self, from: responseData)
        
        return MintingIPFSResult(
            cid: result.Hash,
            ipfsURI: "ipfs://\(result.Hash)",
            gatewayURL: "\(ipfsGatewayURL)/ipfs/\(result.Hash)"
        )
    }
    
    /// Upload JSON metadata to IPFS
    func uploadJSON(_ object: Encodable, filename: String) async throws -> MintingIPFSResult {
        let jsonData = try JSONEncoder().encode(object)
        return try await uploadData(jsonData, filename: filename)
    }
}

// Response from IPFS daemon /api/v0/add
private struct IPFSAddResponse: Decodable {
    let Hash: String
    let Name: String
    let Size: String
}

// MARK: - IPFS Types

enum IPFSError: LocalizedError {
    case invalidURL
    case uploadFailed(String)
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid IPFS URL"
        case .uploadFailed(let reason): return "IPFS upload failed: \(reason)"
        case .notConnected: return "IPFS not connected"
        }
    }
}

// Note: IPFSUploadResponse removed - using IPFSAddResponse for direct IPFS API

struct MintingIPFSResult {
    let cid: String
    let ipfsURI: String
    let gatewayURL: String
}

// MARK: - Contract ABI Encoder

class ContractEncoder {
    
    /// Encode mintDigitalMaster function call
    /// Function: mintDigitalMaster(address[], uint256[], uint256, string, uint256)
    static func encodeMintDigitalMaster(
        owners: [String],
        sharePercentages: [BigUInt],
        royaltyPercentage: BigUInt,
        metadataURI: String,
        requiredSignatures: BigUInt
    ) throws -> Data {
        // Function selector: keccak256("mintDigitalMaster(address[],uint256[],uint256,string,uint256)")[:4]
        let functionSig = "mintDigitalMaster(address[],uint256[],uint256,string,uint256)"
        let selectorHash = functionSig.data(using: .utf8)!.sha3(.keccak256)
        let selector = Data(selectorHash.prefix(4))
        
        // ABI encode the parameters
        var encoded = Data()
        
        // Dynamic types need offsets, static types are inline
        // Layout:
        // [0-31]   offset to owners array
        // [32-63]  offset to sharePercentages array
        // [64-95]  royaltyPercentage (uint256)
        // [96-127] offset to metadataURI string
        // [128-159] requiredSignatures (uint256)
        // [160+]   actual dynamic data
        
        // Calculate offsets (5 params * 32 bytes = 160 bytes to start of dynamic data)
        let headSize = 5 * 32
        
        // Encode owners array
        let ownersEncoded = try encodeAddressArray(owners)
        
        // Encode sharePercentages array
        let sharesEncoded = encodeUint256Array(sharePercentages)
        
        // Encode metadataURI string
        let stringEncoded = encodeString(metadataURI)
        
        // Build offsets
        let ownersOffset = BigUInt(headSize)
        let sharesOffset = ownersOffset + BigUInt(ownersEncoded.count)
        let stringOffset = sharesOffset + BigUInt(sharesEncoded.count)
        
        // Append head (offsets and static values)
        encoded.append(padTo32Bytes(ownersOffset))
        encoded.append(padTo32Bytes(sharesOffset))
        encoded.append(padTo32Bytes(royaltyPercentage))
        encoded.append(padTo32Bytes(stringOffset))
        encoded.append(padTo32Bytes(requiredSignatures))
        
        // Append dynamic data
        encoded.append(ownersEncoded)
        encoded.append(sharesEncoded)
        encoded.append(stringEncoded)
        
        return selector + encoded
    }
    
    private static func encodeAddressArray(_ addresses: [String]) throws -> Data {
        var encoded = Data()
        
        // Array length
        encoded.append(padTo32Bytes(BigUInt(addresses.count)))
        
        // Each address padded to 32 bytes
        for address in addresses {
            let cleaned = address.lowercased().replacingOccurrences(of: "0x", with: "")
            guard let addressData = Data(hexString: cleaned), addressData.count == 20 else {
                throw ContractEncoderError.invalidAddress(address)
            }
            // Left-pad to 32 bytes
            var padded = Data(repeating: 0, count: 12)
            padded.append(addressData)
            encoded.append(padded)
        }
        
        return encoded
    }
    
    private static func encodeUint256Array(_ values: [BigUInt]) -> Data {
        var encoded = Data()
        
        // Array length
        encoded.append(padTo32Bytes(BigUInt(values.count)))
        
        // Each value as 32 bytes
        for value in values {
            encoded.append(padTo32Bytes(value))
        }
        
        return encoded
    }
    
    private static func encodeString(_ string: String) -> Data {
        let stringData = string.data(using: .utf8) ?? Data()
        var encoded = Data()
        
        // String length
        encoded.append(padTo32Bytes(BigUInt(stringData.count)))
        
        // String data padded to 32-byte boundary
        encoded.append(stringData)
        let padding = (32 - (stringData.count % 32)) % 32
        if padding > 0 {
            encoded.append(Data(repeating: 0, count: padding))
        }
        
        return encoded
    }
    
    private static func padTo32Bytes(_ value: BigUInt) -> Data {
        var bytes = value.serialize()
        if bytes.count < 32 {
            bytes = Data(repeating: 0, count: 32 - bytes.count) + bytes
        }
        return bytes
    }
}

enum ContractEncoderError: LocalizedError {
    case invalidAddress(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress(let addr): return "Invalid address: \(addr)"
        }
    }
}

// MARK: - Digital Master Minting Service

@Observable
class DigitalMasterMintingService {
    static let shared = DigitalMasterMintingService()
    
    var isUploading = false
    var isMinting = false
    var progress: Double = 0
    var statusMessage = ""
    var error: String?
    
    @ObservationIgnored
    private let ipfsService = IPFSUploadService.shared
    @ObservationIgnored
    private let walletService = WalletService.shared
    
    // MARK: - Mint Digital Master
    
    /// Stem data for minting
    struct MintingStem {
        let name: String
        let duration: TimeInterval
        let audioData: Data?      // Bounced audio (WAV)
        let midiData: Data?       // Original MIDI file (if MIDI track)
        let isMIDI: Bool          // Whether this was originally a MIDI track
    }
    
    /// Mint a Digital Master using the connected wallet
    func mintDigitalMaster(
        title: String,
        description: String,
        owners: [(address: String, sharePercentage: Int)],
        royaltyPercentage: Int,
        coverImageData: Data?,
        masterAudioData: Data?,   // Full song mix
        stems: [MintingStem]
    ) async throws -> MintResult {
        
        guard let walletAddress = walletService.address else {
            throw MintingError.walletNotConnected
        }
        
        await MainActor.run {
            isUploading = true
            progress = 0.1
            statusMessage = "Preparing files..."
        }
        
        // Step 1: Upload cover image to IPFS
        var coverImageURI: String? = nil
        var coverGatewayURL: String? = nil
        
        if let imageData = coverImageData {
            await MainActor.run {
                statusMessage = "Uploading cover artwork..."
                progress = 0.15
            }
            
            let result = try await ipfsService.uploadData(imageData, filename: "cover.png")
            coverImageURI = result.ipfsURI
            coverGatewayURL = result.gatewayURL
        }
        
        // Step 2: Upload master audio (full song mix) to IPFS
        var masterAudioURI: String? = nil
        
        if let masterData = masterAudioData {
            await MainActor.run {
                statusMessage = "Uploading full song mix..."
                progress = 0.2
            }
            
            let result = try await ipfsService.uploadData(masterData, filename: "master_mix.wav")
            masterAudioURI = result.ipfsURI
        }
        
        // Step 3: Upload STEM audio and MIDI files
        var stemProperties: [StemProperty] = []
        
        for (index, stem) in stems.enumerated() {
            await MainActor.run {
                statusMessage = "Uploading STEM \(index + 1)/\(stems.count): \(stem.name)..."
                progress = 0.25 + (Double(index) / Double(stems.count)) * 0.25
            }
            
            var audioURI: String? = nil
            var midiURI: String? = nil
            
            // Upload audio (bounced from MIDI or original audio)
            if let audioData = stem.audioData {
                let result = try await ipfsService.uploadData(audioData, filename: "stem_\(index)_\(stem.name).wav")
                audioURI = result.ipfsURI
            }
            
            // Upload MIDI file if this was a MIDI track
            if stem.isMIDI, let midiData = stem.midiData {
                let result = try await ipfsService.uploadData(midiData, filename: "stem_\(index)_\(stem.name).mid")
                midiURI = result.ipfsURI
            }
            
            stemProperties.append(StemProperty(
                name: stem.name,
                duration: stem.duration,
                audioURI: audioURI,
                midiURI: midiURI,
                isMIDI: stem.isMIDI
            ))
        }
        
        // Step 4: Build and upload metadata JSON
        await MainActor.run {
            statusMessage = "Uploading metadata..."
            progress = 0.55
        }
        
        let metadata = DigitalMasterMetadata(
            name: title,
            description: description,
            image: coverImageURI ?? "",
            externalURL: "",
            attributes: [
                MetadataAttribute(traitType: "Type", value: "Digital Master"),
                MetadataAttribute(traitType: "STEMs", value: "\(stems.count)"),
                MetadataAttribute(traitType: "Royalty", value: "\(royaltyPercentage)%"),
                MetadataAttribute(traitType: "Owners", value: "\(owners.count)"),
                MetadataAttribute(traitType: "MIDI Tracks", value: "\(stems.filter { $0.isMIDI }.count)")
            ],
            properties: MetadataProperties(
                owners: owners.map { OwnerProperty(address: $0.address, sharePercentage: $0.sharePercentage) },
                royaltyPercentage: royaltyPercentage * 100,  // Convert to basis points
                masterAudioURI: masterAudioURI,
                stems: stemProperties,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                chainId: 507,
                standard: "ERC-721"
            )
        )
        
        let metadataResult = try await ipfsService.uploadJSON(metadata, filename: "metadata.json")
        
        
        await MainActor.run {
            isUploading = false
            isMinting = true
            statusMessage = "Building transaction..."
            progress = 0.6
        }
        
        // Step 4: Encode the contract call
        let ownerAddresses = owners.map { $0.address }
        let sharePercentages = owners.map { BigUInt($0.sharePercentage * 100) }  // Basis points
        let royaltyBasisPoints = BigUInt(royaltyPercentage * 100)
        let requiredSignatures = BigUInt(1)
        
        
        let callData = try ContractEncoder.encodeMintDigitalMaster(
            owners: ownerAddresses,
            sharePercentages: sharePercentages,
            royaltyPercentage: royaltyBasisPoints,
            metadataURI: metadataResult.ipfsURI,
            requiredSignatures: requiredSignatures
        )
        
        
        // Step 5: Get nonce and gas estimate
        await MainActor.run {
            statusMessage = "Preparing transaction..."
            progress = 0.7
        }
        
        let rpcURL = walletService.selectedNetwork.rpcURL
        
        let nonce = try await walletService.fetchNonce(address: walletAddress)
        
        // Step 6: Build and sign transaction
        await MainActor.run {
            statusMessage = "Signing transaction..."
            progress = 0.8
        }
        
        let registryAddress = StoriEnvironment.digitalMasterRegistryAddress
        
        let gasPrice = BigUInt(25_000_000_000)  // 25 Gwei
        let gasLimit = BigUInt(500_000)
        let chainId = BigUInt(507)
        
        
        let transaction = EthereumTransaction.contractCall(
            to: registryAddress,
            data: callData,
            nonce: nonce,
            value: 0,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            chainId: chainId
        )
        
        let signedTx = try walletService.signTransaction(transaction)
        
        // Log last few bytes of raw tx to verify v encoding
        let lastBytes = signedTx.rawTransaction.suffix(100)
        
        // Step 7: Send transaction
        await MainActor.run {
            statusMessage = "Broadcasting transaction..."
            progress = 0.9
        }
        
        let txHash = try await walletService.sendSignedTransaction(signedTx.rawTransaction)
        
        // Step 8: Wait for confirmation (optional - can return early)
        await MainActor.run {
            statusMessage = "Waiting for confirmation..."
            progress = 0.95
        }
        
        // Poll for receipt
        let receipt = try await waitForReceipt(txHash: txHash)
        
        // Parse token ID from logs
        let tokenId = parseTokenIdFromReceipt(receipt)
        
        await MainActor.run {
            isMinting = false
            progress = 1.0
            statusMessage = "Complete!"
        }
        
        return MintResult(
            tokenId: tokenId,
            transactionHash: txHash,
            metadataURI: metadataResult.ipfsURI,
            metadataGatewayURL: metadataResult.gatewayURL,
            coverImageGatewayURL: coverGatewayURL
        )
    }
    
    // MARK: - Helpers
    
    private func waitForReceipt(txHash: String, maxAttempts: Int = 30) async throws -> TransactionReceipt {
        let rpcURL = walletService.selectedNetwork.rpcURL
        
        for _ in 0..<maxAttempts {
            if let receipt = try await fetchReceipt(txHash: txHash, rpcURL: rpcURL) {
                return receipt
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
        }
        
        throw MintingError.transactionTimeout
    }
    
    private func fetchReceipt(txHash: String, rpcURL: URL) async throws -> TransactionReceipt? {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionReceipt",
            "params": [txHash],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            return nil  // Not mined yet
        }
        
        return TransactionReceipt(
            transactionHash: result["transactionHash"] as? String ?? "",
            blockNumber: result["blockNumber"] as? String ?? "",
            status: result["status"] as? String ?? "",
            logs: result["logs"] as? [[String: Any]] ?? []
        )
    }
    
    private func parseTokenIdFromReceipt(_ receipt: TransactionReceipt) -> String {
        // DigitalMasterMinted event topic
        let eventSignature = "DigitalMasterMinted(uint256,address[],uint256[],uint256,string)"
        let eventTopic = eventSignature.data(using: .utf8)!.sha3(.keccak256).toHexString()
        
        for log in receipt.logs {
            guard let topics = log["topics"] as? [String],
                  !topics.isEmpty else { continue }
            
            // Check if this is our event (compare first topic)
            let logTopic = topics[0].replacingOccurrences(of: "0x", with: "").lowercased()
            if logTopic == eventTopic.lowercased() {
                // For indexed uint256, it's in topic[1]
                if topics.count > 1 {
                    let tokenIdHex = topics[1].replacingOccurrences(of: "0x", with: "")
                    if let tokenId = BigUInt(tokenIdHex, radix: 16) {
                        return tokenId.description
                    }
                }
            }
        }
        
        return "0"
    }
    
    // CRITICAL: Protective deinit for @Observable class (ASan Issue #84742+)
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
    // No async resources owned.
    // No deinit required.
}

// MARK: - Minting Types

enum MintingError: LocalizedError {
    case walletNotConnected
    case transactionTimeout
    case transactionFailed(String)
    case insufficientFunds
    
    var errorDescription: String? {
        switch self {
        case .walletNotConnected: return "Wallet not connected"
        case .transactionTimeout: return "Transaction confirmation timed out"
        case .transactionFailed(let msg): return "Transaction failed: \(msg)"
        case .insufficientFunds: return "Insufficient TUS balance"
        }
    }
}

struct MintResult {
    let tokenId: String
    let transactionHash: String
    let metadataURI: String
    let metadataGatewayURL: String
    let coverImageGatewayURL: String?
}

struct TransactionReceipt {
    let transactionHash: String
    let blockNumber: String
    let status: String
    let logs: [[String: Any]]
}

// MARK: - Metadata Types

struct DigitalMasterMetadata: Encodable {
    let name: String
    let description: String
    let image: String
    let externalURL: String
    let attributes: [MetadataAttribute]
    let properties: MetadataProperties
    
    enum CodingKeys: String, CodingKey {
        case name, description, image
        case externalURL = "external_url"
        case attributes, properties
    }
}

struct MetadataAttribute: Encodable {
    let traitType: String
    let value: String
    
    enum CodingKeys: String, CodingKey {
        case traitType = "trait_type"
        case value
    }
}

struct MetadataProperties: Encodable {
    let owners: [OwnerProperty]
    let royaltyPercentage: Int
    let masterAudioURI: String?  // Full song mix audio
    let stems: [StemProperty]
    let createdAt: String
    let chainId: Int
    let standard: String
}

struct OwnerProperty: Encodable {
    let address: String
    let sharePercentage: Int
}

struct StemProperty: Encodable {
    let name: String
    let duration: TimeInterval
    let audioURI: String?   // Bounced audio for this stem
    let midiURI: String?    // Original MIDI file (for MIDI tracks)
    let isMIDI: Bool        // Whether this stem was originally MIDI
}

// Note: Data.init?(hexString:) is defined in SecureKeyStorage.swift
