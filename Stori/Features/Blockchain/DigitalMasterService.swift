//
//  DigitalMasterService.swift
//  Stori
//
//  Created by TellUrStori on 12/9/25.
//

import Foundation

/// Service for fetching Digital Masters and License Instances from the indexer
actor DigitalMasterService {
    /// Shared instance
    static let shared = DigitalMasterService()
    
    private let indexerURL: URL
    
    private init() {
        // Use environment-aware URL
        self.indexerURL = URL(string: StoriEnvironment.indexerGraphQLURL)!
    }
    
    // MARK: - GraphQL Queries
    
    private let digitalMastersByOwnerQuery = """
    query GetDigitalMastersByOwner($ownerAddress: String!) {
        digitalMastersByOwner(ownerAddress: $ownerAddress) {
            id
            tokenId
            title
            description
            imageURI
            masterAudioURI
            metadataURI
            royaltyPercentage
            createdAt
            transactionHash
            blockNumber
            totalRevenue
            totalSales
            owners {
                address
                sharePercentage
            }
            stems {
                name
                duration
                audioURI
                midiURI
                isMIDI
            }
            licenseInstances {
                instanceId
                licenseType
                price
                maxSupply
                totalMinted
            }
        }
    }
    """
    
    private let licenseInstancesByMasterQuery = """
    query GetLicenseInstancesByMaster($masterId: String!) {
        licenseInstancesByMaster(masterId: $masterId) {
            id
            instanceId
            masterId
            licenseType
            price
            maxSupply
            totalMinted
            playsPerInstance
            durationInDays
            isTransferable
            metadataURI
            createdAt
            transactionHash
            blockNumber
            remainingSupply
            isAvailable
        }
    }
    """
    
    private let allLicenseInstancesQuery = """
    query GetAllLicenseInstances($userAddress: String!) {
        allLicenseInstances {
            id
            instanceId
            masterId
            licenseType
            price
            maxSupply
            totalMinted
            playsPerInstance
            durationInDays
            isTransferable
            metadataURI
            createdAt
            transactionHash
            blockNumber
            remainingSupply
            isAvailable
            masterTitle
            masterImageURI
            masterArtist
            masterPreviewAudioURI
            isOwnedByUser(userAddress: $userAddress)
        }
    }
    """
    
    private let digitalMasterByIdQuery = """
    query GetDigitalMasterById($tokenId: String!) {
        digitalMaster(tokenId: $tokenId) {
            id
            tokenId
            title
            description
            imageURI
            masterAudioURI
            metadataURI
            royaltyPercentage
            createdAt
            transactionHash
            blockNumber
            totalRevenue
            totalSales
            owners {
                address
                sharePercentage
            }
            stems {
                name
                duration
                audioURI
                midiURI
                isMIDI
            }
            licenseInstances {
                instanceId
                licenseType
                price
                maxSupply
                totalMinted
            }
        }
    }
    """
    
    // MARK: - Fetch Methods
    
    /// Fetch a single Digital Master by token ID
    func fetchDigitalMasterById(tokenId: String) async throws -> DigitalMasterItem? {
        let variables: [String: Any] = ["tokenId": tokenId]
        
        let response: IndexerGraphQLResponse<DigitalMasterByIdResponse> = try await executeQuery(
            query: digitalMasterByIdQuery,
            variables: variables
        )
        
        guard let data = response.data else {
            if let errors = response.errors, !errors.isEmpty {
                throw DigitalMasterServiceError.graphQLError(errors.first?.message ?? "Unknown error")
            }
            throw DigitalMasterServiceError.noData
        }
        
        return data.digitalMaster?.toDigitalMasterItem()
    }
    
    /// Fetch all Digital Masters owned by an address
    func fetchDigitalMastersByOwner(address: String) async throws -> [DigitalMasterItem] {
        let variables: [String: Any] = ["ownerAddress": address.lowercased()]
        
        let response: IndexerGraphQLResponse<DigitalMastersByOwnerResponse> = try await executeQuery(
            query: digitalMastersByOwnerQuery,
            variables: variables
        )
        
        guard let data = response.data else {
            if let errors = response.errors, !errors.isEmpty {
                throw DigitalMasterServiceError.graphQLError(errors.first?.message ?? "Unknown error")
            }
            throw DigitalMasterServiceError.noData
        }
        
        return data.digitalMastersByOwner.map { $0.toDigitalMasterItem() }
    }
    
    /// Fetch license instances for a Digital Master
    func fetchLicenseInstancesByMaster(masterId: String) async throws -> [LicenseInstance] {
        let variables: [String: Any] = ["masterId": masterId]
        
        let response: IndexerGraphQLResponse<LicenseInstancesByMasterResponse> = try await executeQuery(
            query: licenseInstancesByMasterQuery,
            variables: variables
        )
        
        guard let data = response.data else {
            if let errors = response.errors, !errors.isEmpty {
                throw DigitalMasterServiceError.graphQLError(errors.first?.message ?? "Unknown error")
            }
            throw DigitalMasterServiceError.noData
        }
        
        return data.licenseInstancesByMaster.map { $0.toLicenseInstance() }
    }
    
    /// Fetch all license instances (with master info)
    func fetchAllLicenseInstances(userAddress: String = "") async throws -> [LicenseInstanceWithMaster] {
        let variables: [String: Any] = ["userAddress": userAddress.lowercased()]
        
        let response: IndexerGraphQLResponse<AllLicenseInstancesResponse> = try await executeQuery(
            query: allLicenseInstancesQuery,
            variables: variables
        )
        
        guard let data = response.data else {
            if let errors = response.errors, !errors.isEmpty {
                throw DigitalMasterServiceError.graphQLError(errors.first?.message ?? "Unknown error")
            }
            throw DigitalMasterServiceError.noData
        }
        
        return data.allLicenseInstances.map { $0.toLicenseInstanceWithMaster() }
    }
    
    // MARK: - GraphQL Execution
    
    private func executeQuery<T: Decodable>(query: String, variables: [String: Any]) async throws -> IndexerGraphQLResponse<T> {
        var request = URLRequest(url: indexerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DigitalMasterServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DigitalMasterServiceError.httpError(httpResponse.statusCode, errorBody)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(IndexerGraphQLResponse<T>.self, from: data)
    }
    
    // CRITICAL: Protective deinit for actor (ASan Issue #84742+)
    // Root cause: actor types have implicit actor isolation mechanisms
    // No async resources owned.
    // No deinit required.
}

// MARK: - Error Types

enum DigitalMasterServiceError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)
    case graphQLError(String)
    case noData
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from indexer"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message)"
        case .graphQLError(let message):
            return "GraphQL error: \(message)"
        case .noData:
            return "No data returned from indexer"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        }
    }
}

// MARK: - GraphQL Response Types

struct IndexerGraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [IndexerGraphQLError]?
}

struct IndexerGraphQLError: Decodable {
    let message: String
    let locations: [IndexerGraphQLErrorLocation]?
    let path: [String]?
}

struct IndexerGraphQLErrorLocation: Decodable {
    let line: Int
    let column: Int
}

// MARK: - Response Data Types

struct DigitalMastersByOwnerResponse: Decodable {
    let digitalMastersByOwner: [GraphQLDigitalMaster]
}

struct DigitalMasterByIdResponse: Decodable {
    let digitalMaster: GraphQLDigitalMaster?
}

struct LicenseInstancesByMasterResponse: Decodable {
    let licenseInstancesByMaster: [GraphQLLicenseInstance]
}

struct AllLicenseInstancesResponse: Decodable {
    let allLicenseInstances: [GraphQLLicenseInstanceWithMaster]
}

// MARK: - GraphQL Data Models

struct GraphQLDigitalMaster: Decodable {
    let id: String
    let tokenId: String
    let title: String
    let description: String?
    let imageURI: String?
    let masterAudioURI: String?  // Full song mix audio
    let metadataURI: String
    let royaltyPercentage: Int
    let createdAt: String
    let transactionHash: String
    let blockNumber: String?
    let totalRevenue: String?
    let totalSales: Int?
    let owners: [GraphQLMasterOwner]
    let stems: [GraphQLMasterStem]
    let licenseInstances: [GraphQLLicenseInstanceSummary]?
    
    func toDigitalMasterItem() -> DigitalMasterItem {
        let dateFormatter = ISO8601DateFormatter()
        let createdDate = dateFormatter.date(from: createdAt) ?? Date()
        
        // Convert owners
        let ownerInfos = owners.map { owner in
            MasterOwnerInfo(address: owner.address, sharePercentage: owner.sharePercentage)
        }
        
        // Convert stems
        let stemInfos = stems.map { stem in
            MasterStemInfo(
                name: stem.name,
                duration: stem.duration,
                audioURI: stem.audioURI,
                midiURI: stem.midiURI,
                isMIDI: stem.isMIDI ?? false,
                imageURI: stem.imageURI
            )
        }
        
        // Calculate license count
        let licenseCount = licenseInstances?.count ?? 0
        
        // Parse revenue (comes as string in wei, convert to TUS)
        let revenueWei = Double(totalRevenue ?? "0") ?? 0
        let revenueTUS = revenueWei / 1_000_000_000_000_000_000
        
        return DigitalMasterItem(
            id: id,
            tokenId: tokenId,
            title: title,
            description: description ?? "",
            imageURL: imageURI.flatMap { URL(string: $0) },
            masterAudioURI: masterAudioURI,
            owners: ownerInfos,
            royaltyPercentage: royaltyPercentage,
            stems: stemInfos,
            licenseCount: licenseCount,
            totalRevenue: revenueTUS,
            createdAt: createdDate,
            transactionHash: transactionHash
        )
    }
}

struct GraphQLMasterOwner: Decodable {
    let address: String
    let sharePercentage: Int
}

struct GraphQLMasterStem: Decodable {
    let name: String
    let duration: Double
    let audioURI: String?
    let midiURI: String?    // Original MIDI file (for MIDI tracks)
    let isMIDI: Bool?       // Whether this stem was originally MIDI
    let imageURI: String?
}

struct GraphQLLicenseInstanceSummary: Decodable {
    let instanceId: String
    let licenseType: String
    let price: String
    let maxSupply: Int?
    let totalMinted: Int
}

struct GraphQLLicenseInstance: Decodable {
    let id: String
    let instanceId: String
    let masterId: String
    let licenseType: String
    let price: String
    let maxSupply: Int?
    let totalMinted: Int
    let playsPerInstance: Int?
    let durationInDays: Int?
    let isTransferable: Bool
    let metadataURI: String?
    let createdAt: String
    let transactionHash: String
    let blockNumber: String?
    let remainingSupply: Int?
    let isAvailable: Bool?
    
    func toLicenseInstance() -> LicenseInstance {
        let dateFormatter = ISO8601DateFormatter()
        let createdDate = dateFormatter.date(from: createdAt) ?? Date()
        
        // Parse license type
        let licenseTypeEnum: LicenseType
        switch licenseType.uppercased() {
        case "FULL_OWNERSHIP", "FULLOWNERSHIP":
            licenseTypeEnum = .fullOwnership
        case "STREAMING":
            licenseTypeEnum = .streaming
        case "LIMITED_PLAY", "LIMITEDPLAY":
            licenseTypeEnum = .limitedPlay
        case "TIME_LIMITED", "TIMELIMITED":
            licenseTypeEnum = .timeLimited
        case "COMMERCIAL_LICENSE", "COMMERCIALLICENSE":
            licenseTypeEnum = .commercialLicense
        default:
            licenseTypeEnum = .fullOwnership
        }
        
        // Parse price (comes as string in wei, convert to TUS)
        let priceWei = Double(price) ?? 0
        let priceTUS = priceWei / 1_000_000_000_000_000_000
        
        return LicenseInstance(
            id: id,
            instanceId: instanceId,
            masterId: masterId,
            licenseType: licenseTypeEnum,
            price: priceTUS,
            maxSupply: maxSupply ?? 0,
            totalMinted: totalMinted,
            isTransferable: isTransferable,
            metadataURI: metadataURI,
            createdAt: createdDate,
            transactionHash: transactionHash
        )
    }
}

struct GraphQLLicenseInstanceWithMaster: Decodable {
    let id: String
    let instanceId: String
    let masterId: String
    let licenseType: String
    let price: String
    let maxSupply: Int?
    let totalMinted: Int
    let playsPerInstance: Int?
    let durationInDays: Int?
    let isTransferable: Bool
    let metadataURI: String?
    let createdAt: String
    let transactionHash: String
    let blockNumber: String?
    let remainingSupply: Int?
    let isAvailable: Bool?
    let masterTitle: String?
    let masterImageURI: String?
    let masterArtist: String?
    let masterPreviewAudioURI: String?
    let isOwnedByUser: Bool?
    
    func toLicenseInstanceWithMaster() -> LicenseInstanceWithMaster {
        let dateFormatter = ISO8601DateFormatter()
        let createdDate = dateFormatter.date(from: createdAt) ?? Date()
        
        // Parse license type
        let licenseTypeEnum: LicenseType
        switch licenseType.uppercased() {
        case "FULL_OWNERSHIP", "FULLOWNERSHIP":
            licenseTypeEnum = .fullOwnership
        case "STREAMING":
            licenseTypeEnum = .streaming
        case "LIMITED_PLAY", "LIMITEDPLAY":
            licenseTypeEnum = .limitedPlay
        case "TIME_LIMITED", "TIMELIMITED":
            licenseTypeEnum = .timeLimited
        case "COMMERCIAL_LICENSE", "COMMERCIALLICENSE":
            licenseTypeEnum = .commercialLicense
        default:
            licenseTypeEnum = .fullOwnership
        }
        
        // Parse price (comes as wei string, convert to TUS by dividing by 10^18)
        let priceWei = Double(price) ?? 0
        let priceTUS = priceWei / 1_000_000_000_000_000_000
        
        return LicenseInstanceWithMaster(
            id: id,
            instanceId: instanceId,
            masterId: masterId,
            licenseType: licenseTypeEnum,
            price: priceTUS,
            maxSupply: maxSupply ?? 0,
            totalMinted: totalMinted,
            remainingSupply: remainingSupply ?? (maxSupply ?? 0) - totalMinted,
            isTransferable: isTransferable,
            isAvailable: isAvailable ?? true,
            createdAt: createdDate,
            transactionHash: transactionHash,
            masterTitle: masterTitle ?? "Unknown",
            masterImageURI: masterImageURI,
            masterArtist: masterArtist ?? "Unknown",
            masterPreviewAudioURI: masterPreviewAudioURI,
            isOwnedByCurrentUser: isOwnedByUser ?? false
        )
    }
}

/// License instance with master metadata
struct LicenseInstanceWithMaster: Identifiable {
    let id: String
    let instanceId: String
    let masterId: String
    let licenseType: LicenseType
    let price: Double
    let maxSupply: Int
    let totalMinted: Int
    let remainingSupply: Int
    let isTransferable: Bool
    let isAvailable: Bool
    let createdAt: Date
    let transactionHash: String
    let masterTitle: String
    let masterImageURI: String?
    let masterArtist: String
    let masterPreviewAudioURI: String?
    let isOwnedByCurrentUser: Bool
    
    /// Convert to PurchasedLicense for DRM framework integration
    func toPurchasedLicense() -> PurchasedLicense {
        // Convert IPFS URI to URL if present
        let imageURL: URL? = {
            guard let uri = masterImageURI, !uri.isEmpty else { return nil }
            if uri.hasPrefix("ipfs://") {
                let cid = String(uri.dropFirst(7))
                return URL(string: "http://127.0.0.1:8080/ipfs/\(cid)")
            }
            return URL(string: uri)
        }()
        
        // Determine plays remaining and expiration based on license type
        var playsRemaining: Int? = nil
        var totalPlays: Int? = nil
        var expirationDate: Date? = nil
        
        switch licenseType {
        case .limitedPlay:
            // For limited play, use maxSupply as total plays
            // In production this would come from blockchain state
            totalPlays = 10 // Default
            playsRemaining = 10 // Will be updated by LicenseEnforcer
        case .timeLimited:
            // For time-limited, set expiration 30 days from creation
            // In production this would come from blockchain state
            expirationDate = createdAt.addingTimeInterval(86400 * 30)
        default:
            break
        }
        
        return PurchasedLicense(
            id: id,
            instanceId: instanceId,
            masterId: masterId,
            tokenId: instanceId,
            title: masterTitle,
            artistName: masterArtist,
            description: "License for \(masterTitle)",
            imageURL: imageURL,
            audioURI: masterPreviewAudioURI,
            licenseType: licenseType,
            purchaseDate: createdAt,
            purchasePrice: price,
            transactionHash: transactionHash,
            playsRemaining: playsRemaining,
            totalPlays: totalPlays,
            expirationDate: expirationDate,
            isTransferable: isTransferable
        )
    }
}

// MARK: - Purchase Models

/// A purchase record from the indexer
struct Purchase: Identifiable, Codable {
    let id: String
    let instanceId: String
    let buyer: String
    let quantity: Int
    let totalPaid: String
    let transactionHash: String
    let blockNumber: String
    let timestamp: String
    let licenseInstance: GraphQLLicenseInstance?
    
    struct GraphQLLicenseInstance: Codable {
        let instanceId: String
        let masterId: String
        let licenseType: String
        let price: String
        let maxSupply: Int?
        let totalMinted: Int?
        let masterTitle: String?
        let masterImageURI: String?
        let masterArtist: String?
    }
}

// MARK: - Purchase Response

struct PurchasesByBuyerResponse: Codable {
    let data: DataContainer?
    let errors: [GraphQLError]?
    
    struct DataContainer: Codable {
        let purchasesByBuyer: [Purchase]
    }
}

// MARK: - Purchase Fetching Extension

extension DigitalMasterService {
    
    /// Fetch purchases by buyer address
    func fetchPurchasesByBuyer(buyerAddress: String) async throws -> [LicenseInstanceWithMaster] {
        // Indexer uses lowercase addresses
        let normalizedAddress = buyerAddress.lowercased()
        let query = """
        {
            purchasesByBuyer(buyerAddress: "\(normalizedAddress)") {
                id
                instanceId
                buyer
                quantity
                totalPaid
                transactionHash
                blockNumber
                timestamp
                licenseInstance {
                    instanceId
                    masterId
                    licenseType
                    price
                    maxSupply
                    totalMinted
                    masterTitle
                    masterImageURI
                    masterArtist
                }
            }
        }
        """
        
        guard let url = URL(string: StoriEnvironment.indexerGraphQLURL) else {
            throw DigitalMasterServiceError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DigitalMasterServiceError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(PurchasesByBuyerResponse.self, from: data)
        
        if let errors = decoded.errors, !errors.isEmpty {
            throw DigitalMasterServiceError.graphQLError(errors.first?.message ?? "Unknown error")
        }
        
        guard let purchases = decoded.data?.purchasesByBuyer else {
            return []
        }
        
        // Convert purchases to LicenseInstanceWithMaster
        return purchases.compactMap { purchase -> LicenseInstanceWithMaster? in
            guard let instance = purchase.licenseInstance else { return nil }
            
            let licenseType = licenseTypeFromString(instance.licenseType)
            // Convert wei to TUS (divide by 10^18)
            let priceWei = Double(instance.price) ?? 0.0
            let price = priceWei / 1_000_000_000_000_000_000
            let maxSupply = instance.maxSupply ?? 0
            let totalMinted = instance.totalMinted ?? 0
            
            return LicenseInstanceWithMaster(
                id: instance.instanceId,
                instanceId: instance.instanceId,
                masterId: instance.masterId,
                licenseType: licenseType,
                price: price,
                maxSupply: maxSupply,
                totalMinted: totalMinted,
                remainingSupply: max(0, maxSupply - totalMinted),
                isTransferable: true,
                isAvailable: true,
                createdAt: Date(),
                transactionHash: purchase.transactionHash,
                masterTitle: instance.masterTitle ?? "Untitled",
                masterImageURI: instance.masterImageURI,
                masterArtist: instance.masterArtist ?? "Unknown",
                masterPreviewAudioURI: nil,
                isOwnedByCurrentUser: false
            )
        }
    }
    
    /// Helper to convert license type string to enum
    private func licenseTypeFromString(_ typeString: String) -> LicenseType {
        switch typeString.lowercased() {
        case "fullownership", "full ownership": return .fullOwnership
        case "streaming": return .streaming
        case "limitedplay", "limited play": return .limitedPlay
        case "timelimited", "time limited": return .timeLimited
        case "commerciallicense", "commercial license", "commercial": return .commercialLicense
        default: return .streaming
        }
    }
}

