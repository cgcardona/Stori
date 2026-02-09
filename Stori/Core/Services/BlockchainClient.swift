//
//  BlockchainClient.swift
//  Stori
//
//  🎵 Stori - Blockchain Integration Client
//

//  wallet connections, and real-time data synchronization with the indexer service.
//

import Foundation
import Combine
import SwiftUI
import Network
import Observation

/// Nonisolated owner of an NWPathMonitor for safe deinit cleanup.
private final class MonitorHolder {
    let monitor = NWPathMonitor()
    deinit { monitor.cancel() }
}

// MARK: - Blockchain Client
@MainActor
@Observable
class BlockchainClient {
    
    // MARK: - Observable Properties
    var isConnected: Bool = false
    var connectionStatus: BlockchainConnectionStatus = .disconnected
    var currentWallet: WalletInfo?
    var networkInfo: NetworkInfo?
    var gasPrice: String = "0"
    var pendingTransactions: [PendingTransaction] = []
    var userSTEMs: [STEMToken] = []
    var marketplaceListings: [MarketplaceListing] = []
    var recentActivity: [BlockchainActivity] = []
    
    // MARK: - Configuration (Internal - not observed)
    @ObservationIgnored
    private let rpcURL: URL
    @ObservationIgnored
    private let indexerURL: URL
    @ObservationIgnored
    private let contractAddresses: ContractAddresses
    @ObservationIgnored
    private let session = URLSession.shared
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Network Monitoring
    @ObservationIgnored
    private let monitorHolder = MonitorHolder()
    @ObservationIgnored
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    // MARK: - Wallet Persistence Keys
    private static let walletAddressKey = "TellUrStori_WalletAddress"
    
    // MARK: - Initialization
    init(
        rpcURL: String = "http://127.0.0.1:57751/ext/bc/2Y2VATbw3jVSeZmZzb4ydyjwbYjzd5xfU4d7UWqPHQ2QEK1mki/rpc",
        indexerURL: String = "http://localhost:10003",
        contractAddresses: ContractAddresses = ContractAddresses.tellUrStoriL1
    ) {
        self.rpcURL = URL(string: rpcURL)!
        self.indexerURL = URL(string: indexerURL)!
        self.contractAddresses = contractAddresses
        
        setupNetworkMonitoring()
        
        // Load saved wallet address if it exists
        loadSavedWallet()
        
        // SECURITY: No auto-connect with hardcoded keys
        // User wallet connection happens via QR code payment flow
        // See: TokenizeProjectView for payment workflow
        
        // Initialize connection check
        Task { [weak self] in
            await self?.checkConnections()
        }
    }
    
    // MARK: - Wallet Persistence
    private func loadSavedWallet() {
        if let savedAddress = UserDefaults.standard.string(forKey: Self.walletAddressKey),
           !savedAddress.isEmpty {
            currentWallet = WalletInfo(
                address: savedAddress,
                balance: "0",
                privateKey: nil
            )
            
            // Load user STEMs in background
            Task { [weak self] in
                await self?.loadUserSTEMs()
            }
        }
    }
    
    private func saveWallet(address: String) {
        UserDefaults.standard.set(address, forKey: Self.walletAddressKey)
    }
    
    private func clearSavedWallet() {
        UserDefaults.standard.removeObject(forKey: Self.walletAddressKey)
    }
    
    // MARK: - Network Monitoring
    private func setupNetworkMonitoring() {
        monitorHolder.monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                if path.status == .satisfied {
                    await self?.checkConnections()
                } else {
                    self?.connectionStatus = .disconnected
                    self?.isConnected = false
                }
            }
        }
        monitorHolder.monitor.start(queue: networkQueue)
    }
    
    // MARK: - Connection Management
    func checkConnections() async {
        do {
            // Check indexer service via GraphQL query instead of /health
            let graphqlURL = indexerURL.appendingPathComponent("graphql")
            var request = URLRequest(url: graphqlURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 5
            
            let query = """
            {"query":"{ indexerStatus { isRunning totalMasters } }"}
            """
            request.httpBody = query.data(using: .utf8)
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                connectionStatus = .error("Indexer service unavailable")
                isConnected = false
                return
            }
            
            // Parse GraphQL response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any],
               let status = dataObj["indexerStatus"] as? [String: Any],
               let isRunning = status["isRunning"] as? Bool,
               isRunning {
                connectionStatus = .connected
                isConnected = true
                
                // Load initial data
                await loadInitialData()
            } else {
                connectionStatus = .error("Indexer not responding")
                isConnected = false
            }
            
        } catch {
            connectionStatus = .error("Connection failed: \(error.localizedDescription)")
            isConnected = false
        }
    }
    
    // MARK: - Initial Data Loading
    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { [weak self] group in
            group.addTask { [weak self] in await self?.loadNetworkInfo() }
            group.addTask { [weak self] in await self?.loadGasPrice() }
            group.addTask { [weak self] in await self?.loadUserSTEMs() }
            group.addTask { [weak self] in await self?.loadMarketplaceListings() }
            group.addTask { [weak self] in await self?.loadRecentActivity() }
        }
    }
    
    // MARK: - Network Information
    private func loadNetworkInfo() async {
        do {
            let query = """
            query GetNetworkInfo {
              marketStats {
                totalVolume
                totalSales
                activeListings
                floorPrice
                lastUpdated
              }
              stemStats {
                totalStems
                totalCreators
                totalSupply
                lastUpdated
              }
            }
            """
            
            let response: GraphQLResponse<NetworkStatsData> = try await executeGraphQLQuery(query: query)
            
            if let data = response.data {
                networkInfo = NetworkInfo(
                    chainId: 507, // Stori L1
                    networkName: "Stori L1",
                    totalVolume: data.marketStats.totalVolume,
                    totalSTEMs: data.stemStats.totalStems,
                    totalCreators: data.stemStats.totalCreators,
                    activeListings: data.marketStats.activeListings,
                    floorPrice: data.marketStats.floorPrice
                )
            }
        } catch {
        }
    }
    
    private func loadGasPrice() async {
        // For now, use a fixed gas price for local development
        gasPrice = "20000000000" // 20 gwei
    }
    
    // MARK: - User STEMs
    private func loadUserSTEMs() async {
        guard let walletAddress = currentWallet?.address else { return }
        
        do {
            let query = """
            {
              stems {
                edges {
                  node {
                    tokenId
                    name
                    description
                    creator
                    genre
                    tags
                    duration
                    royaltyPercentage
                    totalSupply
                    createdAt
                    audioIPFSHash
                    imageIPFSHash
                  }
                }
              }
            }
            """
            
            let response: GraphQLResponse<UserSTEMsData> = try await executeGraphQLQuery(query: query)
            
            if let data = response.data {
                // Filter for user's STEMs
                userSTEMs = data.stems.edges.compactMap { edge in
                    guard edge.node.creator.lowercased() == walletAddress.lowercased() else { return nil }
                    
                    return STEMToken(
                        id: edge.node.tokenId,
                        tokenId: edge.node.tokenId,
                        name: edge.node.name,
                        description: edge.node.description ?? "Professional STEM for music production",
                        creator: edge.node.creator,
                        stemType: STEMType.fromGenre(edge.node.genre ?? "Other"),
                        duration: Int(edge.node.duration ?? "180") ?? 180,
                        bpm: 120, // Default BPM
                        key: nil,
                        genre: edge.node.genre,
                        totalSupply: edge.node.totalSupply,
                        floorPrice: nil,
                        lastSalePrice: nil,
                        totalVolume: "0",
                        createdAt: ISO8601DateFormatter().date(from: edge.node.createdAt) ?? Date(),
                        audioCID: edge.node.audioIPFSHash,
                        imageCID: edge.node.imageIPFSHash
                    )
                }
            }
        } catch {
        }
    }
    
    // MARK: - Marketplace Data
    private func loadMarketplaceListings() async {
        do {
            let query = """
            {
              stems {
                edges {
                  node {
                    tokenId
                    name
                    genre
                    creator
                    totalSupply
                    duration
                    royaltyPercentage
                    createdAt
                    audioIPFSHash
                    imageIPFSHash
                  }
                }
              }
              marketStats {
                totalVolume
                activeListings
                floorPrice
              }
            }
            """
            
            let response: GraphQLResponse<MarketplaceData> = try await executeGraphQLQuery(query: query)
            
            if let data = response.data {
                marketplaceListings = data.stems.edges.enumerated().map { index, edge in
                    // Create mock listings from our real STEM data
                    let priceVariations = ["0.75", "1.2", "1.5", "1.8", "2.0", "2.5", "3.2", "5.0", "8.0"]
                    let mockPrice = priceVariations[index % priceVariations.count]
                    
                    return MarketplaceListing(
                        id: "listing_\(edge.node.tokenId)",
                        listingId: edge.node.tokenId,
                        seller: edge.node.creator,
                        stem: STEMToken(
                            id: edge.node.tokenId,
                            tokenId: edge.node.tokenId,
                            name: edge.node.name,
                            description: "Professional \(edge.node.genre ?? "Music") STEM for production",
                            creator: edge.node.creator,
                            stemType: STEMType.fromGenre(edge.node.genre ?? "Other"),
                            duration: Int(edge.node.duration ?? "180") ?? 180,
                            bpm: 120, // Default BPM
                            key: nil,
                            genre: edge.node.genre,
                            totalSupply: edge.node.totalSupply,
                            floorPrice: mockPrice,
                            lastSalePrice: nil,
                            totalVolume: "0",
                            createdAt: ISO8601DateFormatter().date(from: edge.node.createdAt) ?? Date(),
                            audioCID: edge.node.audioIPFSHash,
                            imageCID: edge.node.imageIPFSHash
                        ),
                        amount: "5", // Mock available amount
                        pricePerToken: mockPrice,
                        totalPrice: String(Double(mockPrice)! * 5.0),
                        expiration: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
                        createdAt: ISO8601DateFormatter().date(from: edge.node.createdAt) ?? Date()
                    )
                }
            }
        } catch {
        }
    }
    
    // MARK: - Recent Activity
    private func loadRecentActivity() async {
        do {
            let query = """
            {
              recentActivity {
                type
                tokenId
                from
                to
                amount
                timestamp
                transactionHash
                blockNumber
              }
            }
            """
            
            let response: GraphQLResponse<RecentActivityResponse> = try await executeGraphQLQuery(query: query)
            
            if let data = response.data {
                recentActivity = data.recentActivity.map { activity in
                    BlockchainActivity(
                        type: ActivityType(rawValue: activity.type.lowercased()) ?? .unknown,
                        tokenId: activity.tokenId,
                        address: activity.from, // Use 'from' as primary address
                        timestamp: ISO8601DateFormatter().date(from: activity.timestamp) ?? Date(),
                        transactionHash: activity.transactionHash,
                        blockNumber: activity.blockNumber ?? "0"
                    )
                }
            }
        } catch {
        }
    }
    
    // MARK: - STEM Minting
    func mintSTEM(
        audioData: Data,
        metadata: STEMMetadata,
        supply: String = "1000",
        imageData: Data? = nil  // Phase 8: Optional image data
    ) async throws -> PendingTransaction {
        
        guard let wallet = currentWallet else {
            throw BlockchainError.noWalletConnected
        }
        
        // Step 1: Upload audio to IPFS
        let audioUploadResult = try await uploadToIPFS(data: audioData, contentType: "audio/wav")
        
        // Step 1.5: Upload image to IPFS if provided (Phase 8)
        var imageUploadResult: IPFSUploadResult?
        if let imageData = imageData {
            imageUploadResult = try await uploadToIPFS(data: imageData, contentType: "image/png")
        }
        
        // Step 2: Create and upload metadata
        var fullMetadata = metadata
        fullMetadata.audioURL = "ipfs://\(audioUploadResult.cid)"
        if let imageCID = imageUploadResult?.cid {
            fullMetadata.imageURL = "ipfs://\(imageCID)"
        }
        
        let metadataJSON = try JSONEncoder().encode(fullMetadata)
        let metadataUploadResult = try await uploadToIPFS(data: metadataJSON, contentType: "application/json")
        
        // Step 3: Create pending transaction
        var txData: [String: String] = [
            "metadataURI": "ipfs://\(metadataUploadResult.cid)",
            "supply": supply,
            "audioCID": audioUploadResult.cid,
            "metadataCID": metadataUploadResult.cid
        ]
        
        // Phase 8: Include image CID if available
        if let imageCID = imageUploadResult?.cid {
            txData["imageCID"] = imageCID
        }
        
        let pendingTx = PendingTransaction(
            id: UUID(),
            type: .mintSTEM,
            status: .pending,
            hash: nil,
            from: wallet.address,
            to: contractAddresses.stemContract,
            value: "0",
            gasLimit: "500000",
            gasPrice: gasPrice,
            data: txData,
            createdAt: Date()
        )
        
        // Add to pending transactions
        pendingTransactions.append(pendingTx)
        
        // Step 4: Submit transaction (simulated for now)
        try await submitTransaction(pendingTx)
        
        return pendingTx
    }
    
    // MARK: - Marketplace Operations
    func createListing(
        tokenId: String,
        amount: String,
        pricePerToken: String,
        expiration: Date?
    ) async throws -> PendingTransaction {
        
        guard let wallet = currentWallet else {
            throw BlockchainError.noWalletConnected
        }
        
        let pendingTx = PendingTransaction(
            id: UUID(),
            type: .createListing,
            status: .pending,
            hash: nil,
            from: wallet.address,
            to: contractAddresses.marketplaceContract,
            value: "0",
            gasLimit: "300000",
            gasPrice: gasPrice,
            data: [
                "tokenId": tokenId,
                "amount": amount,
                "pricePerToken": pricePerToken,
                "expiration": expiration?.timeIntervalSince1970.description ?? "0"
            ],
            createdAt: Date()
        )
        
        pendingTransactions.append(pendingTx)
        try await submitTransaction(pendingTx)
        
        return pendingTx
    }
    
    func buyListing(listingId: String, amount: String) async throws -> PendingTransaction {
        guard let wallet = currentWallet else {
            throw BlockchainError.noWalletConnected
        }
        
        // Find the listing to get the total price
        guard let listing = marketplaceListings.first(where: { $0.listingId == listingId }) else {
            throw BlockchainError.listingNotFound
        }
        
        let totalPrice = (BigInt(listing.pricePerToken) ?? BigInt(0)) * (BigInt(amount) ?? BigInt(0))
        
        let pendingTx = PendingTransaction(
            id: UUID(),
            type: .buyListing,
            status: .pending,
            hash: nil,
            from: wallet.address,
            to: contractAddresses.marketplaceContract,
            value: totalPrice.description,
            gasLimit: "400000",
            gasPrice: gasPrice,
            data: [
                "listingId": listingId,
                "amount": amount
            ],
            createdAt: Date()
        )
        
        pendingTransactions.append(pendingTx)
        try await submitTransaction(pendingTx)
        
        return pendingTx
    }
    
    // MARK: - IPFS Integration
    private func uploadToIPFS(data: Data, contentType: String) async throws -> IPFSUploadResult {
        let uploadURL = indexerURL.appendingPathComponent("api/ipfs/upload")
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BlockchainError.ipfsUploadFailed
        }
        
        let uploadResult = try JSONDecoder().decode(IPFSUploadResult.self, from: responseData)
        return uploadResult
    }
    
    // MARK: - Transaction Submission
    private func submitTransaction(_ transaction: PendingTransaction) async throws {
        // For now, simulate transaction submission
        // In a real implementation, this would sign and broadcast the transaction
        
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
        
        // Update transaction status
        if let index = pendingTransactions.firstIndex(where: { $0.id == transaction.id }) {
            var updatedTx = pendingTransactions[index]
            updatedTx.status = .confirmed
            updatedTx.hash = "0x" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            pendingTransactions[index] = updatedTx
            
            // Refresh data after successful transaction
            await loadInitialData()
        }
    }
    
    // MARK: - Payment Detection
    /// Get the current block number from the blockchain
    func getCurrentBlockNumber() async throws -> Int {
        let blockRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_blockNumber",
            "params": [],
            "id": 1
        ]
        
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: blockRequest)
        
        let (data, _) = try await session.data(for: request)
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blockHex = response["result"] as? String,
              let blockNumber = Int(blockHex.dropFirst(2), radix: 16) else {
            throw BlockchainError.networkError
        }
        
        return blockNumber
    }
    
    /// Poll blockchain for payment confirmation (EIP-681 compliant)
    /// Used in QR code payment workflow - checks if user has paid the required fee with matching request ID
    func checkForPayment(
        to feeRecipientAddress: String,
        minimumAmount: String,
        requestId: String,
        fromAddress: String? = nil
    ) async throws -> PaymentConfirmation? {
        
        // Build JSON-RPC request to get recent blocks
        let blockCountToCheck = 10 // Check last 10 blocks (~20 seconds on 2s block time)
        
        // Get latest block number
        let latestBlockRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_blockNumber",
            "params": [],
            "id": 1
        ]
        
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: latestBlockRequest)
        
        let (blockData, _) = try await session.data(for: request)
        guard let blockResponse = try? JSONSerialization.jsonObject(with: blockData) as? [String: Any],
              let latestBlockHex = blockResponse["result"] as? String,
              let latestBlock = Int(latestBlockHex.dropFirst(2), radix: 16) else {
            throw BlockchainError.networkError
        }
        
        // Determine which blocks to check
        let checkFromBlock = max(0, latestBlock - blockCountToCheck)
        
        // Convert request ID to hex for comparison
        let requestIdData = Data(requestId.utf8)
        let requestIdHex = "0x" + requestIdData.map { String(format: "%02x", $0) }.joined()
        
        
        // Check each block for matching transactions
        for blockNum in checkFromBlock...latestBlock {
            let blockHex = String(format: "0x%x", blockNum)
            
            // Get block with full transaction details
            let blockRequest: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "eth_getBlockByNumber",
                "params": [blockHex, true], // true = include full tx objects
                "id": 1
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: blockRequest)
            
            let (data, _) = try await session.data(for: request)
            guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = response["result"] as? [String: Any],
                  let transactions = result["transactions"] as? [[String: Any]] else {
                continue
            }
            
            // Check each transaction in the block
            for tx in transactions {
                guard let to = tx["to"] as? String,
                      let from = tx["from"] as? String,
                      let valueHex = tx["value"] as? String,
                      let hash = tx["hash"] as? String else {
                    continue
                }
                
                // Get transaction data field (contains request ID in EIP-681)
                let txData = tx["input"] as? String ?? "0x"
                
                // Convert hex value to decimal
                let value = BigInt(hex: valueHex)
                let minValue = BigInt(minimumAmount) // minimumAmount is already decimal string
                
                // Check if this transaction matches our criteria (EIP-681)
                let toMatches = to.lowercased() == feeRecipientAddress.lowercased()
                let amountSufficient = value.value >= minValue.value
                let fromMatches = fromAddress == nil || from.lowercased() == fromAddress?.lowercased()
                let requestIdMatches = txData.lowercased() == requestIdHex.lowercased()
                
                if toMatches && amountSufficient && fromMatches && requestIdMatches {
                    
                    return PaymentConfirmation(
                        transactionHash: hash,
                        from: from,
                        to: to,
                        amount: value.value,
                        blockNumber: blockNum
                    )
                }
            }
        }
        
        // No matching payment found
        return nil
    }
    
    // MARK: - GraphQL Helper
    private func executeGraphQLQuery<T: Codable>(
        query: String,
        variables: [String: Any]? = nil
    ) async throws -> GraphQLResponse<T> {
        let graphqlURL = indexerURL.appendingPathComponent("graphql")
        
        var request = URLRequest(url: graphqlURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables ?? [:]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BlockchainError.graphqlRequestFailed
        }
        
        return try JSONDecoder().decode(GraphQLResponse<T>.self, from: data)
    }
    
    // MARK: - Wallet Management
    func connectWallet(address: String, privateKey: String? = nil) {
        currentWallet = WalletInfo(
            address: address,
            balance: "0",
            privateKey: privateKey
        )
        
        // Persist wallet address
        saveWallet(address: address)
        
        // Reload user data
        Task {
            await loadUserSTEMs()
        }
    }
    
    func disconnectWallet() {
        currentWallet = nil
        userSTEMs = []
        pendingTransactions = []
        
        // Clear saved wallet address
        clearSavedWallet()
    }
    
    // MARK: - Refresh Data
    func refreshData() async {
        await loadInitialData()
    }
    
    // No deinit needed — MonitorHolder.deinit cancels the NWPathMonitor via RAII.
}

// MARK: - Supporting Types

// MARK: - Connection Status
enum BlockchainConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var description: String {
        switch self {
        case .disconnected:
            return "Indexer Offline"
        case .connecting:
            return "Connecting to Indexer..."
        case .connected:
            return "Indexer Connected"
        case .error(let message):
            return "Indexer Error: \(message)"
        }
    }
}

// MARK: - Contract Addresses
struct ContractAddresses {
    let stemContract: String
    let marketplaceContract: String
    
    static let localhost = ContractAddresses(
        stemContract: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
        marketplaceContract: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
    )
    
    static let tellUrStoriL1 = ContractAddresses(
        stemContract: "0xA4cD3b0Eb6E5Ab5d8CE4065BcCD70040ADAB1F00",
        marketplaceContract: "0xa4DfF80B4a1D748BF28BC4A271eD834689Ea3407"
    )
    
    static let fuji = ContractAddresses(
        stemContract: "0x...", // To be deployed
        marketplaceContract: "0x..." // To be deployed
    )
}

// MARK: - Wallet Info
struct WalletInfo {
    let address: String
    let balance: String
    let privateKey: String?
}

// MARK: - Network Info
struct NetworkInfo {
    let chainId: Int
    let networkName: String
    let totalVolume: String
    let totalSTEMs: Int
    let totalCreators: Int
    let activeListings: Int
    let floorPrice: String?
}

// MARK: - STEM Token
struct STEMToken: Identifiable, Codable, Equatable {
    let id: String
    let tokenId: String
    let name: String
    let description: String
    let creator: String
    let stemType: STEMType
    let duration: Int
    let bpm: Int
    let key: String?
    let genre: String?
    let totalSupply: String
    let floorPrice: String?
    let lastSalePrice: String?
    let totalVolume: String
    let createdAt: Date
    let audioCID: String?
    let imageCID: String?
}

// MARK: - STEM Type
enum STEMType: String, CaseIterable, Codable {
    case drums = "drums"
    case bass = "bass"
    case melody = "melody"
    case vocals = "vocals"
    case harmony = "harmony"
    case effects = "effects"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .drums: return "Drums"
        case .bass: return "Bass"
        case .melody: return "Melody"
        case .vocals: return "Vocals"
        case .harmony: return "Harmony"
        case .effects: return "Effects"
        case .other: return "Other"
        }
    }
    
    var emoji: String {
        switch self {
        case .drums: return "🥁"
        case .bass: return "🎸"
        case .melody: return "🎹"
        case .vocals: return "🎤"
        case .harmony: return "🎵"
        case .effects: return "✨"
        case .other: return "🎶"
        }
    }
    
    static func fromGenre(_ genre: String) -> STEMType {
        let lowercased = genre.lowercased()
        if lowercased.contains("drum") || lowercased.contains("beat") || lowercased.contains("percussion") {
            return .drums
        } else if lowercased.contains("bass") {
            return .bass
        } else if lowercased.contains("vocal") || lowercased.contains("voice") {
            return .vocals
        } else if lowercased.contains("melody") || lowercased.contains("lead") {
            return .melody
        } else if lowercased.contains("harmony") || lowercased.contains("chord") {
            return .harmony
        } else if lowercased.contains("effect") || lowercased.contains("fx") {
            return .effects
        } else {
            return .other
        }
    }
}

// MARK: - STEM Metadata
struct STEMMetadata: Codable {
    let name: String
    let description: String
    let stemType: String
    let duration: Int?
    let bpm: Int?
    let key: String?
    let genre: String?
    let format: String
    let sampleRate: Int?
    let bitDepth: Int?
    let channels: Int?
    var audioURL: String?
    var imageURL: String?
    let createdAt: String
    
    init(
        name: String,
        description: String,
        stemType: STEMType,
        duration: Int? = nil,
        bpm: Int? = nil,
        key: String? = nil,
        genre: String? = nil,
        format: String = "wav",
        sampleRate: Int? = 48000,
        bitDepth: Int? = 16,
        channels: Int? = 2
    ) {
        self.name = name
        self.description = description
        self.stemType = stemType.rawValue
        self.duration = duration
        self.bpm = bpm
        self.key = key
        self.genre = genre
        self.format = format
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.createdAt = ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: - Marketplace Listing
struct MarketplaceListing: Identifiable {
    let id: String
    let listingId: String
    let seller: String
    let stem: STEMToken
    let amount: String
    let pricePerToken: String
    let totalPrice: String
    let expiration: Date?
    let createdAt: Date
}

// MARK: - Blockchain Activity
struct BlockchainActivity: Identifiable {
    let id = UUID()
    let type: ActivityType
    let tokenId: String
    let address: String
    let timestamp: Date
    let transactionHash: String
    let blockNumber: String
}

enum ActivityType: String {
    case mint = "mint"
    case transfer = "transfer"
    case listing = "listing"
    case sale = "sale"
    case offer = "offer"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .mint: return "Minted"
        case .transfer: return "Transferred"
        case .listing: return "Listed"
        case .sale: return "Sold"
        case .offer: return "Offer Made"
        case .unknown: return "Unknown"
        }
    }
    
    var emoji: String {
        switch self {
        case .mint: return "✨"
        case .transfer: return "📤"
        case .listing: return "🏷️"
        case .sale: return "💰"
        case .offer: return "💡"
        case .unknown: return "❓"
        }
    }
    
    var color: Color {
        switch self {
        case .mint: return .green
        case .transfer: return .blue
        case .listing: return .orange
        case .sale: return .purple
        case .offer: return .yellow
        case .unknown: return .gray
        }
    }
}

// MARK: - Pending Transaction
struct PendingTransaction: Identifiable {
    let id: UUID
    let type: TransactionType
    var status: TransactionStatus
    var hash: String?
    let from: String
    let to: String
    let value: String
    let gasLimit: String
    let gasPrice: String
    let data: [String: String]
    let createdAt: Date
}

enum TransactionType {
    case mintSTEM
    case createListing
    case buyListing
    case makeOffer
    case acceptOffer
    
    var displayName: String {
        switch self {
        case .mintSTEM: return "Mint STEM"
        case .createListing: return "Create Listing"
        case .buyListing: return "Buy STEM"
        case .makeOffer: return "Make Offer"
        case .acceptOffer: return "Accept Offer"
        }
    }
}

enum TransactionStatus {
    case pending
    case confirmed
    case failed
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Blockchain Errors
enum BlockchainError: LocalizedError {
    case noWalletConnected
    case insufficientBalance
    case transactionFailed
    case contractNotFound
    case listingNotFound
    case ipfsUploadFailed
    case graphqlRequestFailed
    case invalidAddress
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .noWalletConnected:
            return "No wallet connected"
        case .insufficientBalance:
            return "Insufficient balance"
        case .transactionFailed:
            return "Transaction failed"
        case .contractNotFound:
            return "Smart contract not found"
        case .listingNotFound:
            return "Marketplace listing not found"
        case .ipfsUploadFailed:
            return "Failed to upload to IPFS"
        case .graphqlRequestFailed:
            return "GraphQL request failed"
        case .invalidAddress:
            return "Invalid wallet address"
        case .networkError:
            return "Network connection error"
        }
    }
}

// MARK: - API Response Types
struct IndexerHealthResponse: Codable {
    let status: String
    let services: HealthServices
}

struct HealthServices: Codable {
    let database: Bool
    let ipfs: Bool
    let blockchain: Bool
}

struct GraphQLResponse<T: Codable>: Codable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Codable {
    let message: String
    let locations: [GraphQLLocation]?
    let path: [String]?
}

struct GraphQLLocation: Codable {
    let line: Int
    let column: Int
}

struct IPFSUploadResult: Codable {
    let cid: String
    let url: String
    let size: Int
}

// MARK: - GraphQL Data Types
struct NetworkStatsData: Codable {
    let marketStats: MarketStatsData
    let stemStats: STEMStatsData
}

struct MarketStatsData: Codable {
    let totalVolume: String
    let totalSales: Int
    let activeListings: Int
    let floorPrice: String?
    let lastUpdated: String
}

struct STEMStatsData: Codable {
    let totalStems: Int
    let totalCreators: Int
    let totalSupply: String
    let lastUpdated: String
}

struct UserSTEMsData: Codable {
    let stems: STEMConnection
}

struct STEMConnection: Codable {
    let edges: [STEMEdge]
}

struct STEMEdge: Codable {
    let node: STEMNode
}

struct STEMNode: Codable {
    let tokenId: String
    let name: String
    let description: String?
    let creator: String
    let genre: String?
    let tags: [String]?
    let duration: String?
    let royaltyPercentage: String
    let totalSupply: String
    let createdAt: String
    let audioIPFSHash: String?
    let imageIPFSHash: String?
}

struct MarketplaceListingsData: Codable {
    let listings: ListingConnection
}

struct MarketplaceData: Codable {
    let stems: STEMConnection
    let marketStats: MarketStatsData
}

struct ListingConnection: Codable {
    let edges: [ListingEdge]
}

struct ListingEdge: Codable {
    let node: ListingNode
}

struct ListingNode: Codable {
    let id: String
    let listingId: String
    let seller: String
    let stem: STEMNode
    let amount: String
    let pricePerToken: String
    let totalPrice: String
    let expiration: String?
    let createdAt: String
}

struct RecentActivityData: Codable {
    let recentActivity: [ActivityNode]
}

struct RecentActivityResponse: Codable {
    let recentActivity: [RecentActivityNode]
}

struct RecentActivityNode: Codable {
    let type: String
    let tokenId: String
    let from: String
    let to: String
    let amount: String
    let timestamp: String
    let transactionHash: String
    let blockNumber: String?
}

struct ActivityNode: Codable {
    let type: String
    let tokenId: String
    let address: String
    let timestamp: String
    let transactionHash: String
    let blockNumber: String
}

// MARK: - Payment Confirmation
struct PaymentConfirmation {
    let transactionHash: String
    let from: String
    let to: String
    let amount: String  // in wei
    let blockNumber: Int
}

// MARK: - BigInt Helper
struct BigInt {
    let value: String
    
    init(_ value: String) {
        self.value = value
    }
    
    init(_ value: Int) {
        self.value = String(value)
    }
    
    init(hex: String) {
        // Remove 0x prefix if present
        let cleanHex = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        
        // Convert hex to decimal string
        if cleanHex.isEmpty {
            self.value = "0"
            return
        }
        
        // Try simple conversion for reasonable values
        if let decimalValue = UInt64(cleanHex, radix: 16) {
            self.value = String(decimalValue)
        } else {
            // For very large numbers, return the hex as-is with a note
            // In production, use a proper BigInt library
            self.value = cleanHex
        }
    }
    
    static func +(lhs: BigInt, rhs: BigInt) -> BigInt {
        // Simplified addition - in real implementation would use proper BigInt library
        let left = Int(lhs.value) ?? 0
        let right = Int(rhs.value) ?? 0
        return BigInt(left + right)
    }
    
    static func *(lhs: BigInt, rhs: BigInt) -> BigInt {
        // Simplified multiplication - in real implementation would use proper BigInt library
        let left = Int(lhs.value) ?? 0
        let right = Int(rhs.value) ?? 0
        return BigInt(left * right)
    }
    
    var description: String {
        return value
    }
}
