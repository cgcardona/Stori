//
//  StoriEnvironment.swift
//  Stori
//
//  Created by TellUrStori on 12/8/25.
//

import Foundation

/// Environment configuration for TellUrStori blockchain services
/// Provides URLs for frontend, IPFS, and indexer based on build configuration
/// Note: All blockchain transactions use direct wallet signing (no signing service)
enum StoriEnvironment {
    
    // MARK: - Base URLs
    
    #if DEBUG
    /// Base URL for the marketplace frontend
    static let baseURL = "http://localhost:3000"
    /// IPFS gateway for content retrieval
    static let ipfsGatewayURL = "http://127.0.0.1:8080"
    /// GraphQL indexer URL for blockchain queries
    static let indexerGraphQLURL = "http://localhost:10003/graphql"
    /// Indexer service base URL (for IPFS uploads, etc.)
    static let indexerServiceURL = "http://localhost:10003"
    #else
    /// Base URL for the marketplace frontend
    static let baseURL = "https://example.com"
    /// IPFS gateway for content retrieval
    static let ipfsGatewayURL = "https://ipfs.example.com"
    /// GraphQL indexer URL for blockchain queries
    static let indexerGraphQLURL = "https://api.example.com/graphql"
    /// Indexer service base URL (for IPFS uploads, etc.)
    static let indexerServiceURL = "https://api.example.com"
    #endif
    
    // MARK: - Contract Addresses (Stori L1 deployment - 2026-01-20)
    
    #if DEBUG
    /// DigitalMasterRegistry contract address (ERC-721)
    static let digitalMasterRegistryAddress = "0x95CA0a568236fC7413Cd2b794A7da24422c2BBb6"
    /// DigitalInstanceFactory contract address (ERC-1155 licenses)
    static let digitalInstanceFactoryAddress = "0x789a5FDac2b37FCD290fb2924382297A6AE65860"
    /// TellUrStoriSTEM contract address (ERC-1155)
    static let tellUrStoriSTEMAddress = "0xE3573540ab8A1C4c754Fd958Dc1db39BBE81b208"
    /// STEMMarketplace contract address  
    static let stemMarketplaceAddress = "0x8B3BC4270BE2abbB25BC04717830bd1Cc493a461"
    #else
    /// DigitalMasterRegistry contract address (production)
    static let digitalMasterRegistryAddress = "0x0000000000000000000000000000000000000000"
    /// DigitalInstanceFactory contract address (production)
    static let digitalInstanceFactoryAddress = "0x0000000000000000000000000000000000000000"
    /// TellUrStoriSTEM contract address (production)
    static let tellUrStoriSTEMAddress = "0x0000000000000000000000000000000000000000"
    /// STEMMarketplace contract address (production)
    static let stemMarketplaceAddress = "0x0000000000000000000000000000000000000000"
    #endif
    
    // MARK: - Chain Configuration
    
    /// Avalanche L1 Chain ID for Stori
    static let chainId = 507
    
    /// Chain name
    static let chainName = "Stori L1"
    
    /// Native token symbol
    static let tokenSymbol = "TUS"
    
    /// RPC URL for the chain
    #if DEBUG
    // Stori L1 - deployed via avalanche-cli 2026-01-20
    // BlockchainID: AaBEDb6ANQ5uHFSmeGPsTZiwQiCz3nK9xDYW9c2UvnaT7ENGa
    static let rpcURL = "http://127.0.0.1:9654/ext/bc/AaBEDb6ANQ5uHFSmeGPsTZiwQiCz3nK9xDYW9c2UvnaT7ENGa/rpc"
    #else
    static let rpcURL = "https://rpc.example.com/ext/bc/tellurstoriDAW/rpc"
    #endif
    
    // MARK: - URL Builders
    
    /// Build URL for a Digital Master page
    /// - Parameter tokenId: The token ID (can be hex or numeric)
    /// - Returns: Full URL string to the master page
    static func masterURL(tokenId: String) -> String {
        return "\(baseURL)/master/\(tokenId)"
    }
    
    /// Build URL for a marketplace item page
    /// - Parameter tokenId: The token ID
    /// - Returns: Full URL string to the marketplace item
    static func marketplaceItemURL(tokenId: String) -> String {
        return "\(baseURL)/marketplace/digital-master/\(tokenId)"
    }
    
    /// Build URL for a license instance page
    /// - Parameter instanceId: The instance ID
    /// - Returns: Full URL string to the license instance
    static func licenseInstanceURL(instanceId: String) -> String {
        return "\(baseURL)/marketplace/license/\(instanceId)"
    }
    
    /// Build URL for user's Digital Masters page
    /// - Parameter address: Wallet address
    /// - Returns: Full URL string to the user's masters page
    static func userMastersURL(address: String) -> String {
        return "\(baseURL)/creator/\(address)/masters"
    }
    
    /// Convert IPFS URI to gateway URL
    /// - Parameter ipfsURI: IPFS URI (ipfs://...)
    /// - Returns: HTTP gateway URL
    static func ipfsToGatewayURL(_ ipfsURI: String) -> String {
        if ipfsURI.hasPrefix("ipfs://") {
            let hash = String(ipfsURI.dropFirst(7))
            return "\(ipfsGatewayURL)/ipfs/\(hash)"
        }
        return ipfsURI
    }
}

