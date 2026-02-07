//
//  NFTService.swift
//  Stori
//
//  Service for fetching NFTs (STEMs and Digital Masters) from the indexer
//

import Foundation
import SwiftUI
import Combine
import Observation

// MARK: - NFT Models

/// A STEM NFT (ERC1155)
struct STEMNFT: Identifiable, Codable {
    let tokenId: String
    let name: String
    let description: String
    let creator: String
    let genre: String
    let tags: [String]
    let duration: Int
    let royaltyPercentage: Int
    let totalSupply: String
    let createdAt: String
    let audioIPFSHash: String
    let imageIPFSHash: String
    let balance: String?  // User's balance of this token
    
    var id: String { tokenId }
    
    /// Duration formatted as mm:ss
    var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// IPFS gateway URL for the image
    func imageURL(gateway: String = "http://127.0.0.1:8080") -> URL? {
        guard !imageIPFSHash.isEmpty else { return nil }
        return URL(string: "\(gateway)/ipfs/\(imageIPFSHash)")
    }
    
    /// IPFS gateway URL for the audio
    func audioURL(gateway: String = "http://127.0.0.1:8080") -> URL? {
        guard !audioIPFSHash.isEmpty else { return nil }
        return URL(string: "\(gateway)/ipfs/\(audioIPFSHash)")
    }
}

/// A Digital Master NFT (ERC721)
struct DigitalMasterNFT: Identifiable, Codable {
    let tokenId: String
    let title: String
    let description: String
    let metadataURI: String
    let imageURI: String?
    let owners: [OwnerShare]
    let royaltyPercentage: Int
    let isLocked: Bool
    let instanceContract: String?
    let createdAt: String?
    
    var id: String { tokenId }
    
    struct OwnerShare: Codable {
        let address: String
        let sharePercentage: Int
    }
    
    /// Returns a URL for the image, converting IPFS URIs to gateway URLs
    func imageURL(gateway: String = "http://127.0.0.1:8080") -> URL? {
        guard let uri = imageURI, !uri.isEmpty else { return nil }
        
        if uri.hasPrefix("ipfs://") {
            let cid = String(uri.dropFirst(7))
            return URL(string: "\(gateway)/ipfs/\(cid)")
        }
        
        return URL(string: uri)
    }
}

/// Combined NFT portfolio
struct NFTPortfolio {
    var stems: [STEMNFT] = []
    var digitalMasters: [DigitalMasterNFT] = []
    var isLoading: Bool = false
    var error: String?
    
    var totalNFTs: Int {
        stems.count + digitalMasters.count
    }
    
    var isEmpty: Bool {
        stems.isEmpty && digitalMasters.isEmpty
    }
}

// MARK: - NFT Service

/// Service for fetching NFTs from the blockchain indexer
@MainActor
@Observable
class NFTService {
    
    static let shared = NFTService()
    
    var portfolio = NFTPortfolio()
    
    @ObservationIgnored
    private let indexerURL: URL
    @ObservationIgnored
    private let ipfsGateway: String
    
    private init() {
        // Default to local indexer
        self.indexerURL = URL(string: "http://127.0.0.1:10003/graphql")!
        self.ipfsGateway = "http://127.0.0.1:8080"
    }
    
    /// Fetch all NFTs owned by an address
    func fetchNFTs(for address: String) async {
        portfolio.isLoading = true
        portfolio.error = nil
        
        
        do {
            // Fetch STEMs and Digital Masters in parallel
            async let stemsTask = fetchSTEMs(for: address)
            async let mastersTask = fetchDigitalMasters(for: address)
            
            let (stems, masters) = try await (stemsTask, mastersTask)
            
            
            portfolio.stems = stems
            portfolio.digitalMasters = masters
            portfolio.isLoading = false
            
        } catch {
            // Log the error for debugging
            
            // TODO: For STEMs, keep empty since that contract isn't deployed yet
            portfolio.stems = []
            
            // For Digital Masters, try to recover or show empty
            portfolio.digitalMasters = []
            portfolio.error = nil // Don't show error - just show empty state
            portfolio.isLoading = false
        }
    }
    
    /// Fetch STEMs owned by an address
    /// Note: STEM contract is not deployed yet, so this returns empty for now
    private func fetchSTEMs(for address: String) async throws -> [STEMNFT] {
        // STEM contract (ERC1155 for individual stems) is not deployed yet
        // When it is, we'll query the indexer for stems owned by this address
        // For now, return empty array
        return []
    }
    
    /// Fetch Digital Masters owned by an address
    private func fetchDigitalMasters(for address: String) async throws -> [DigitalMasterNFT] {
        // Query matches the indexer schema exactly
        let query = """
        query($ownerAddress: String!) {
            digitalMastersByOwner(ownerAddress: $ownerAddress) {
                tokenId
                title
                description
                imageURI
                metadataURI
                owners {
                    address
                    sharePercentage
                }
                royaltyPercentage
                createdAt
                blockNumber
                transactionHash
                licenseInstances {
                    instanceId
                    licenseType
                    price
                    totalMinted
                    maxSupply
                }
            }
        }
        """
        
        var request = URLRequest(url: indexerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        // Normalize address to lowercase (indexer stores lowercase)
        let normalizedAddress = address.lowercased()
        
        
        let body: [String: Any] = [
            "query": query,
            "variables": ["ownerAddress": normalizedAddress]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NFTError.networkError("Server returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        
        // Debug: print raw response
        if let jsonString = String(data: data, encoding: .utf8) {
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let masters = dataObj["digitalMastersByOwner"] as? [[String: Any]] else {
            // Check for GraphQL errors
            if let errors = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["errors"] as? [[String: Any]] {
                let errorMsg = errors.first?["message"] as? String ?? "Unknown GraphQL error"
                throw NFTError.parseError(errorMsg)
            }
            return []
        }
        
        
        // Convert to DigitalMasterNFT objects
        return masters.compactMap { parseDigitalMaster(from: $0) }
    }
    
    // MARK: - Parsing Helpers
    
    private func parseSTEM(from dict: [String: Any]) -> STEMNFT? {
        guard let tokenId = dict["tokenId"] as? String,
              let name = dict["name"] as? String else {
            return nil
        }
        
        return STEMNFT(
            tokenId: tokenId,
            name: name,
            description: dict["description"] as? String ?? "",
            creator: dict["creator"] as? String ?? "",
            genre: dict["genre"] as? String ?? "Unknown",
            tags: dict["tags"] as? [String] ?? [],
            duration: (dict["duration"] as? Int) ?? Int(dict["duration"] as? String ?? "0") ?? 0,
            royaltyPercentage: (dict["royaltyPercentage"] as? Int) ?? Int(dict["royaltyPercentage"] as? String ?? "0") ?? 0,
            totalSupply: dict["totalSupply"] as? String ?? "0",
            createdAt: dict["createdAt"] as? String ?? "",
            audioIPFSHash: dict["audioIPFSHash"] as? String ?? "",
            imageIPFSHash: dict["imageIPFSHash"] as? String ?? "",
            balance: nil
        )
    }
    
    private func parseDigitalMaster(from dict: [String: Any]) -> DigitalMasterNFT? {
        guard let tokenId = dict["tokenId"] as? String else {
            return nil
        }
        
        var owners: [DigitalMasterNFT.OwnerShare] = []
        if let ownersArray = dict["owners"] as? [[String: Any]] {
            owners = ownersArray.compactMap { ownerDict in
                guard let address = ownerDict["address"] as? String else {
                    return nil
                }
                // sharePercentage could be Int or Double depending on how indexer returns it
                let share: Int
                if let intShare = ownerDict["sharePercentage"] as? Int {
                    share = intShare
                } else if let doubleShare = ownerDict["sharePercentage"] as? Double {
                    share = Int(doubleShare)
                } else {
                    share = 0
                }
                return DigitalMasterNFT.OwnerShare(address: address, sharePercentage: share)
            }
        }
        
        // Parse royalty percentage (could be Int or Double)
        let royaltyPercentage: Int
        if let intRoyalty = dict["royaltyPercentage"] as? Int {
            royaltyPercentage = intRoyalty
        } else if let doubleRoyalty = dict["royaltyPercentage"] as? Double {
            royaltyPercentage = Int(doubleRoyalty)
        } else {
            royaltyPercentage = 0
        }
        
        // Check if there's an active instance contract (has license instances)
        var instanceContract: String? = nil
        if let licenseInstances = dict["licenseInstances"] as? [[String: Any]], !licenseInstances.isEmpty {
            // If there are license instances, we have an instance contract
            instanceContract = "active"  // Placeholder since we don't have the actual address
        }
        
        // Determine if locked based on having license instances
        let isLocked = instanceContract != nil
        
        return DigitalMasterNFT(
            tokenId: tokenId,
            title: dict["title"] as? String ?? "Untitled",
            description: dict["description"] as? String ?? "",
            metadataURI: dict["metadataURI"] as? String ?? "",
            imageURI: dict["imageURI"] as? String,
            owners: owners,
            royaltyPercentage: royaltyPercentage,
            isLocked: isLocked,
            instanceContract: instanceContract,
            createdAt: dict["createdAt"] as? String
        )
    }
    
    // MARK: - Cleanup
}

// MARK: - NFT Errors

enum NFTError: LocalizedError {
    case networkError(String)
    case parseError(String)
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .notFound: return "NFT not found"
        }
    }
}
