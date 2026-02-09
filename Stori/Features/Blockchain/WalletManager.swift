//
//  WalletManager.swift
//  Stori
//
//  Created by TellUrStori on 12/8/25.
//

import SwiftUI
import Combine
import Observation

/// Manages wallet connection state for blockchain interactions
/// Stores wallet address for querying Digital Masters and signing transactions
@MainActor
@Observable
class WalletManager {
    /// Singleton instance for app-wide access
    static let shared = WalletManager()
    
    // MARK: - Observable State
    
    /// Connected wallet address (persisted via UserDefaults)
    @ObservationIgnored
    private var _storedWalletAddress: String {
        get { UserDefaults.standard.string(forKey: "connectedWalletAddress") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "connectedWalletAddress") }
    }
    
    /// Whether a wallet is currently connected
    var isConnected: Bool = false
    
    /// Current wallet balance in TUS (fetched from blockchain)
    var balance: String = "0"
    
    /// Loading state for balance fetch
    var isLoadingBalance: Bool = false
    
    /// Error message if wallet operations fail
    var errorMessage: String?
    
    // MARK: - Computed Properties
    
    /// Current wallet address
    var walletAddress: String {
        get { _storedWalletAddress }
        set {
            _storedWalletAddress = newValue
            isConnected = !newValue.isEmpty
        }
    }
    
    /// Shortened wallet address for display (0x1234...5678)
    var shortAddress: String {
        guard walletAddress.count > 10 else { return walletAddress }
        return "\(walletAddress.prefix(6))...\(walletAddress.suffix(4))"
    }
    
    /// Checksummed wallet address (EIP-55)
    var checksumAddress: String {
        // For now, return as-is. Full EIP-55 checksum would require keccak256
        return walletAddress
    }
    
    // MARK: - Initialization
    
    private init() {
        // Restore connection state from stored address
        isConnected = !_storedWalletAddress.isEmpty
        
        // If connected, fetch balance
        if isConnected {
            Task { [weak self] in
                await self?.refreshBalance()
            }
        }
    }
    
    
    // MARK: - Wallet Operations
    
    /// Connect a wallet by address
    /// - Parameter address: Ethereum-compatible address (0x prefixed, 42 chars)
    /// - Parameter blockchainClient: Optional BlockchainClient to sync with
    /// - Returns: True if connection successful, false if validation failed
    @discardableResult
    func connect(address: String, blockchainClient: BlockchainClient? = nil) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate address format
        guard isValidAddress(trimmed) else {
            errorMessage = "Invalid wallet address. Must be 0x followed by 40 hex characters."
            return false
        }
        
        walletAddress = trimmed
        errorMessage = nil
        
        
        // Sync with BlockchainClient if provided
        blockchainClient?.connectWallet(address: trimmed)
        
        // Fetch balance
        Task { [weak self] in
            await self?.refreshBalance()
        }
        
        // Post notification for UI updates (includes address for BlockchainClient sync)
        NotificationCenter.default.post(name: .walletConnected, object: trimmed)
        
        return true
    }
    
    /// Disconnect the current wallet
    /// - Parameter blockchainClient: Optional BlockchainClient to sync with
    func disconnect(blockchainClient: BlockchainClient? = nil) {
        let previousAddress = walletAddress
        walletAddress = ""
        balance = "0"
        errorMessage = nil
        
        
        // Sync with BlockchainClient if provided
        blockchainClient?.disconnectWallet()
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .walletDisconnected, object: nil)
    }
    
    /// Validate Ethereum address format
    /// - Parameter address: Address to validate
    /// - Returns: True if valid format
    func isValidAddress(_ address: String) -> Bool {
        // Must start with 0x
        guard address.hasPrefix("0x") else { return false }
        
        // Must be exactly 42 characters (0x + 40 hex chars)
        guard address.count == 42 else { return false }
        
        // Remaining characters must be valid hex
        let hexChars = address.dropFirst(2)
        let validHex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return hexChars.unicodeScalars.allSatisfy { validHex.contains($0) }
    }
    
    /// Refresh wallet balance from the blockchain
    @MainActor
    func refreshBalance() async {
        guard isConnected else { return }
        
        isLoadingBalance = true
        defer { isLoadingBalance = false }
        
        do {
            // Call signing service to get balance
            let balanceResult = try await fetchBalanceFromService()
            balance = balanceResult
        } catch {
            // Don't update balance on error, keep previous value
        }
    }
    
    /// Fetch balance directly from RPC
    private func fetchBalanceFromService() async throws -> String {
        guard let url = URL(string: StoriEnvironment.rpcURL) else {
            throw WalletError.invalidURL
        }
        
        // JSON-RPC request for eth_getBalance
        let rpcRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [walletAddress, "latest"],
            "id": 1
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: rpcRequest)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WalletError.networkError
        }
        
        struct RPCResponse: Codable {
            let result: String?
            let error: RPCError?
        }
        
        struct RPCError: Codable {
            let message: String
        }
        
        let decoded = try JSONDecoder().decode(RPCResponse.self, from: data)
        
        guard let hexBalance = decoded.result else {
            throw WalletError.networkError
        }
        
        // Convert hex to formatted TUS balance
        let cleanHex = hexBalance.hasPrefix("0x") ? String(hexBalance.dropFirst(2)) : hexBalance
        guard let weiValue = UInt64(cleanHex, radix: 16) else {
            return "0.0000"
        }
        
        let tusValue = Double(weiValue) / 1_000_000_000_000_000_000.0
        return String(format: "%.4f", tusValue)
    }
    
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
}

// MARK: - Wallet Errors

enum WalletError: LocalizedError {
    case invalidAddress
    case invalidURL
    case networkError
    case signingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid wallet address format"
        case .invalidURL:
            return "Invalid service URL"
        case .networkError:
            return "Network error while connecting to wallet service"
        case .signingError(let message):
            return "Signing error: \(message)"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let walletConnected = Notification.Name("walletConnected")
    static let walletDisconnected = Notification.Name("walletDisconnected")
}

