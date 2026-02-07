//
//  LibraryService.swift
//  Stori
//
//  Created by TellUrStori on 12/10/25.
//

import Foundation

/// Service for fetching purchased licenses from the indexer
actor LibraryService {
    /// Shared instance
    static let shared = LibraryService()
    
    private let indexerURL: URL
    
    private init() {
        self.indexerURL = URL(string: StoriEnvironment.indexerGraphQLURL)!
    }
    
    // MARK: - GraphQL Queries
    
    private let purchasedLicensesByOwnerQuery = """
    query GetPurchasedLicensesByOwner($ownerAddress: String!) {
        purchasedLicensesByOwner(ownerAddress: $ownerAddress) {
            id
            instanceId
            masterId
            tokenId
            quantity
            purchasePrice
            purchaseDate
            transactionHash
            instance {
                licenseType
                maxSupply
                totalMinted
                playsPerInstance
                durationInDays
                isTransferable
                metadataURI
                master {
                    tokenId
                    title
                    description
                    imageURI
                    stems {
                        name
                        duration
                        audioURI
                    }
                    owners {
                        address
                        sharePercentage
                    }
                }
            }
        }
    }
    """
    
    // MARK: - Fetch Methods
    
    /// Fetch all purchased licenses for an owner
    func fetchPurchasedLicenses(ownerAddress: String) async throws -> [PurchasedLicense] {
        let variables: [String: Any] = ["ownerAddress": ownerAddress.lowercased()]
        
        let response: IndexerGraphQLResponse<PurchasedLicensesResponse> = try await executeQuery(
            query: purchasedLicensesByOwnerQuery,
            variables: variables
        )
        
        guard let data = response.data else {
            if let errors = response.errors, !errors.isEmpty {
                throw LibraryServiceError.graphQLError(errors.first?.message ?? "Unknown error")
            }
            throw LibraryServiceError.noData
        }
        
        return data.purchasedLicensesByOwner.compactMap { $0.toPurchasedLicense() }
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
            throw LibraryServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LibraryServiceError.httpError(httpResponse.statusCode, errorBody)
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

enum LibraryServiceError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)
    case graphQLError(String)
    case noData
    
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
        }
    }
}

// MARK: - Response Data Types

struct PurchasedLicensesResponse: Decodable {
    let purchasedLicensesByOwner: [GraphQLPurchasedLicense]
}

struct GraphQLPurchasedLicense: Decodable {
    let id: String
    let instanceId: String
    let masterId: String
    let tokenId: String
    let quantity: Int
    let purchasePrice: String
    let purchaseDate: String
    let transactionHash: String
    let instance: GraphQLLicenseInstanceFull?
    
    func toPurchasedLicense() -> PurchasedLicense? {
        guard let instance = instance else { return nil }
        
        let dateFormatter = ISO8601DateFormatter()
        let purchasedDate = dateFormatter.date(from: purchaseDate) ?? Date()
        
        // Parse license type
        let licenseTypeEnum: LicenseType
        switch instance.licenseType.uppercased() {
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
        let priceWei = Double(purchasePrice) ?? 0
        let priceTUS = priceWei / 1_000_000_000_000_000_000
        
        // Calculate expiration for time-limited licenses
        var expirationDate: Date? = nil
        if licenseTypeEnum == .timeLimited, let days = instance.durationInDays {
            expirationDate = Calendar.current.date(byAdding: .day, value: days, to: purchasedDate)
        }
        
        // Get audio URI from first stem
        let audioURI = instance.master?.stems.first?.audioURI
        
        // Get artist name from first owner
        let artistName = instance.master?.owners.first?.address ?? "Unknown Artist"
        let shortArtist = "\(artistName.prefix(6))...\(artistName.suffix(4))"
        
        return PurchasedLicense(
            id: id,
            instanceId: instanceId,
            masterId: masterId,
            tokenId: tokenId,
            title: instance.master?.title ?? "Untitled",
            artistName: shortArtist,
            description: instance.master?.description ?? "",
            imageURL: instance.master?.imageURI.flatMap { URL(string: $0) },
            audioURI: audioURI,
            licenseType: licenseTypeEnum,
            purchaseDate: purchasedDate,
            purchasePrice: priceTUS,
            transactionHash: transactionHash,
            playsRemaining: instance.playsPerInstance,
            totalPlays: instance.playsPerInstance,
            expirationDate: expirationDate,
            isTransferable: instance.isTransferable
        )
    }
}

struct GraphQLLicenseInstanceFull: Decodable {
    let licenseType: String
    let maxSupply: Int?
    let totalMinted: Int
    let playsPerInstance: Int?
    let durationInDays: Int?
    let isTransferable: Bool
    let metadataURI: String?
    let master: GraphQLMasterForLibrary?
}

struct GraphQLMasterForLibrary: Decodable {
    let tokenId: String
    let title: String
    let description: String?
    let imageURI: String?
    let stems: [GraphQLStemForLibrary]
    let owners: [GraphQLOwnerForLibrary]
}

struct GraphQLStemForLibrary: Decodable {
    let name: String
    let duration: Double
    let audioURI: String?
}

struct GraphQLOwnerForLibrary: Decodable {
    let address: String
    let sharePercentage: Int
}

