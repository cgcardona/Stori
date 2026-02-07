//
//  TransactionHistoryService.swift
//  Stori
//
//  Service for fetching and managing transaction history
//

import Foundation
import SwiftUI
import Combine
import BigInt
import Observation

// MARK: - Transaction Models

/// Transaction type for filtering
enum TxHistoryType: String, CaseIterable, Identifiable {
    case all = "All"
    case send = "Send"
    case receive = "Receive"
    case purchase = "Purchase"
    case nftMint = "NFT Mint"
    case contractCall = "Contract"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "arrow.left.arrow.right"
        case .send: return "arrow.up.circle"
        case .receive: return "arrow.down.circle"
        case .purchase: return "cart.fill"
        case .nftMint: return "sparkles"
        case .contractCall: return "gearshape"
        }
    }
}

/// A blockchain transaction for history display
struct TxHistoryEntry: Identifiable {
    let id: String  // Transaction hash
    let hash: String
    let type: TxHistoryType
    let from: String
    let to: String?
    let value: BigUInt
    let gasUsed: BigUInt?
    let gasPrice: BigUInt?
    let timestamp: Date
    let blockNumber: UInt64
    let status: TransactionStatus
    let contractAddress: String?
    let tokenId: String?
    let tokenAmount: String?
    
    enum TransactionStatus: String {
        case pending = "Pending"
        case confirmed = "Confirmed"
        case failed = "Failed"
    }
    
    /// Value formatted as TUS
    var formattedValue: String {
        let decimals = BigUInt(10).power(18)
        let whole = value / decimals
        let fraction = (value % decimals) / BigUInt(10).power(14)  // 4 decimal places
        
        if fraction == 0 {
            return "\(whole) TUS"
        } else {
            return "\(whole).\(String(format: "%04d", Int(fraction))) TUS"
        }
    }
    
    /// Gas cost formatted
    var formattedGasCost: String? {
        guard let gasUsed = gasUsed, let gasPrice = gasPrice else { return nil }
        let cost = gasUsed * gasPrice
        let decimals = BigUInt(10).power(18)
        let costInTUS = Double(cost) / Double(decimals)
        return String(format: "%.6f TUS", costInTUS)
    }
    
    /// Truncated hash for display
    var truncatedHash: String {
        guard hash.count > 16 else { return hash }
        let prefix = hash.prefix(10)
        let suffix = hash.suffix(6)
        return "\(prefix)...\(suffix)"
    }
    
    /// Truncated address for display
    func truncatedAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        let prefix = address.prefix(8)
        let suffix = address.suffix(4)
        return "\(prefix)...\(suffix)"
    }
}

/// Filter options for transaction history
struct TxHistoryFilter {
    var type: TxHistoryType = .all
    var dateRange: DateRange = .all
    var searchQuery: String = ""
    
    enum DateRange: String, CaseIterable, Identifiable {
        case all = "All Time"
        case today = "Today"
        case week = "Last 7 Days"
        case month = "Last 30 Days"
        
        var id: String { rawValue }
        
        var startDate: Date? {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .all: return nil
            case .today: return calendar.startOfDay(for: now)
            case .week: return calendar.date(byAdding: .day, value: -7, to: now)
            case .month: return calendar.date(byAdding: .day, value: -30, to: now)
            }
        }
    }
}

// MARK: - Transaction History Service

@MainActor
@Observable
class TransactionHistoryService {
    
    static let shared = TransactionHistoryService()
    
    var transactions: [TxHistoryEntry] = []
    var isLoading = false
    var error: String?
    var filter = TxHistoryFilter()
    
    @ObservationIgnored
    private var currentAddress: String?
    @ObservationIgnored
    private let indexerURL = URL(string: "http://127.0.0.1:10003/graphql")!
    
    private init() {}
    
    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when
    /// the runtime deinits this object on MainActor/task-local context.
    nonisolated deinit {}
    
    /// Filtered transactions based on current filter
    var filteredTransactions: [TxHistoryEntry] {
        var result = transactions
        
        // Filter by type
        if filter.type != .all {
            result = result.filter { $0.type == filter.type }
        }
        
        // Filter by date
        if let startDate = filter.dateRange.startDate {
            result = result.filter { $0.timestamp >= startDate }
        }
        
        // Filter by search query
        if !filter.searchQuery.isEmpty {
            let query = filter.searchQuery.lowercased()
            result = result.filter { tx in
                tx.hash.lowercased().contains(query) ||
                tx.from.lowercased().contains(query) ||
                (tx.to?.lowercased().contains(query) ?? false)
            }
        }
        
        return result
    }
    
    /// Fetch transaction history for an address
    func fetchTransactions(for address: String) async {
        currentAddress = address
        isLoading = true
        error = nil
        
        var allTransactions: [TxHistoryEntry] = []
        
        do {
            // Fetch purchases from indexer
            let purchases = try await fetchPurchasesFromIndexer(address: address)
            allTransactions.append(contentsOf: purchases)
        } catch {
        }
        
        do {
            // Fetch native TUS transfers from RPC
            let network = WalletService.shared.selectedNetwork
            let transfers = try await fetchNativeTransfersFromRPC(address: address, rpcURL: network.rpcURL)
            allTransactions.append(contentsOf: transfers)
        } catch {
        }
        
        // Sort by timestamp (newest first) and deduplicate by hash
        var seen = Set<String>()
        self.transactions = allTransactions
            .filter { tx in
                guard !seen.contains(tx.hash) else { return false }
                seen.insert(tx.hash)
                return true
            }
            .sorted { $0.timestamp > $1.timestamp }
        
        self.isLoading = false
        
        if self.transactions.isEmpty {
            // No error, just empty state
            self.error = nil
        }
    }
    
    /// Refresh current transactions
    func refresh() async {
        guard let address = currentAddress else { return }
        await fetchTransactions(for: address)
    }
    
    // MARK: - Fetch Purchases from Indexer
    
    private func fetchPurchasesFromIndexer(address: String) async throws -> [TxHistoryEntry] {
        let normalizedAddress = address.lowercased()
        
        let query = """
        query($buyerAddress: String!) {
            purchasesByBuyer(buyerAddress: $buyerAddress) {
                id
                instanceId
                buyer
                quantity
                totalPaid
                transactionHash
                blockNumber
                timestamp
                licenseInstance {
                    masterTitle
                    licenseType
                    masterId
                }
            }
        }
        """
        
        var request = URLRequest(url: indexerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        let body: [String: Any] = [
            "query": query,
            "variables": ["buyerAddress": normalizedAddress]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TransactionHistoryError.networkError("Server returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let purchases = dataObj["purchasesByBuyer"] as? [[String: Any]] else {
            return []
        }
        
        // Convert purchases to TxHistoryEntry
        return purchases.compactMap { purchase -> TxHistoryEntry? in
            guard let txHash = purchase["transactionHash"] as? String,
                  let totalPaidStr = purchase["totalPaid"] as? String,
                  let blockNumberStr = purchase["blockNumber"] as? String else {
                return nil
            }
            
            // Parse the value (TUS as string with decimals, e.g. "0.5")
            let valueInTUS = Double(totalPaidStr) ?? 0
            let valueWei = BigUInt(valueInTUS * 1e18)
            
            // Parse block number
            let blockNumber = UInt64(blockNumberStr) ?? 0
            
            // Parse timestamp (ISO string)
            let timestamp: Date
            if let timestampStr = purchase["timestamp"] as? String {
                let formatter = ISO8601DateFormatter()
                timestamp = formatter.date(from: timestampStr) ?? Date()
            } else {
                timestamp = Date()
            }
            
            // Get license info for display
            let licenseInstance = purchase["licenseInstance"] as? [String: Any]
            let masterTitle = licenseInstance?["masterTitle"] as? String
            let licenseType = licenseInstance?["licenseType"] as? String
            
            // Factory contract is the "to" address for purchases
            let factoryContract = "0x789a5FDac2b37FCD290fb2924382297A6AE65860"
            
            return TxHistoryEntry(
                id: txHash,
                hash: txHash,
                type: .purchase,
                from: normalizedAddress,
                to: factoryContract,
                value: valueWei,
                gasUsed: nil,
                gasPrice: nil,
                timestamp: timestamp,
                blockNumber: blockNumber,
                status: .confirmed,
                contractAddress: factoryContract,
                tokenId: purchase["instanceId"] as? String,
                tokenAmount: "\(purchase["quantity"] as? Int ?? 1) \(licenseType ?? "License") - \(masterTitle ?? "Unknown")"
            )
        }
    }
    
    // MARK: - RPC Fetching for Native Transfers
    
    /// Fetch native TUS transfers by scanning recent blocks
    private func fetchNativeTransfersFromRPC(address: String, rpcURL: URL) async throws -> [TxHistoryEntry] {
        let normalizedAddress = address.lowercased()
        
        // Get latest block number
        let latestBlock = try await getLatestBlockNumber(rpcURL: rpcURL)
        
        // Scan last 500 blocks (adjust as needed for performance)
        let fromBlock: UInt64 = latestBlock > 500 ? latestBlock - 500 : 0
        
        var transactions: [TxHistoryEntry] = []
        
        // Fetch blocks and extract transactions involving this address
        // We'll sample blocks to avoid too many requests
        let step: UInt64 = 10  // Check every 10th block for better performance
        var block = fromBlock
        
        while block <= latestBlock {
            do {
                let blockTxs = try await getTransactionsInBlock(
                    blockNumber: block,
                    address: normalizedAddress,
                    rpcURL: rpcURL
                )
                transactions.append(contentsOf: blockTxs)
            } catch {
                // Skip this block if there's an error
            }
            
            block += step
        }
        
        // Also check the most recent blocks without stepping
        for recentBlock in (latestBlock - min(20, latestBlock))...latestBlock {
            if recentBlock > fromBlock + (step - 1) { // Avoid duplicates with stepping
                do {
                    let blockTxs = try await getTransactionsInBlock(
                        blockNumber: recentBlock,
                        address: normalizedAddress,
                        rpcURL: rpcURL
                    )
                    transactions.append(contentsOf: blockTxs)
                } catch {
                    // Skip this block
                }
            }
        }
        
        return transactions
    }
    
    private func getLatestBlockNumber(rpcURL: URL) async throws -> UInt64 {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_blockNumber",
            "params": [],
            "id": 1
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultHex = json["result"] as? String else {
            throw TransactionHistoryError.parseError("Failed to get block number")
        }
        
        let hex = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        guard let blockNumber = UInt64(hex, radix: 16) else {
            throw TransactionHistoryError.parseError("Invalid block number")
        }
        
        return blockNumber
    }
    
    private func getTransactionsInBlock(
        blockNumber: UInt64,
        address: String,
        rpcURL: URL
    ) async throws -> [TxHistoryEntry] {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        let blockHex = "0x" + String(blockNumber, radix: 16)
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBlockByNumber",
            "params": [blockHex, true],  // true = include full transaction objects
            "id": 1
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let transactions = result["transactions"] as? [[String: Any]] else {
            return []
        }
        
        // Get block timestamp
        let timestamp: Date
        if let timestampHex = result["timestamp"] as? String {
            let hex = timestampHex.hasPrefix("0x") ? String(timestampHex.dropFirst(2)) : timestampHex
            if let unix = UInt64(hex, radix: 16) {
                timestamp = Date(timeIntervalSince1970: Double(unix))
            } else {
                timestamp = Date()
            }
        } else {
            timestamp = Date()
        }
        
        // Filter transactions involving this address
        var entries: [TxHistoryEntry] = []
        
        for tx in transactions {
            guard let from = (tx["from"] as? String)?.lowercased(),
                  let txHash = tx["hash"] as? String else {
                continue
            }
            
            let to = (tx["to"] as? String)?.lowercased()
            
            // Check if this transaction involves our address
            let isOutgoing = from == address
            let isIncoming = to == address
            
            guard isOutgoing || isIncoming else { continue }
            
            // Parse value
            let value: BigUInt
            if let valueHex = tx["value"] as? String {
                let hex = valueHex.hasPrefix("0x") ? String(valueHex.dropFirst(2)) : valueHex
                value = BigUInt(hex, radix: 16) ?? BigUInt(0)
            } else {
                value = BigUInt(0)
            }
            
            // Skip zero-value transactions (likely contract calls) unless they're contract interactions
            let input = tx["input"] as? String ?? "0x"
            let isContractCall = input.count > 2
            
            if value == 0 && !isContractCall {
                continue
            }
            
            // Parse gas info
            let gasUsed: BigUInt? = nil  // Would need receipt for this
            let gasPrice: BigUInt?
            if let gasPriceHex = tx["gasPrice"] as? String {
                let hex = gasPriceHex.hasPrefix("0x") ? String(gasPriceHex.dropFirst(2)) : gasPriceHex
                gasPrice = BigUInt(hex, radix: 16)
            } else {
                gasPrice = nil
            }
            
            // Determine transaction type
            let type: TxHistoryType
            if isContractCall && value == 0 {
                type = .contractCall
            } else if isOutgoing {
                type = .send
            } else {
                type = .receive
            }
            
            let entry = TxHistoryEntry(
                id: txHash,
                hash: txHash,
                type: type,
                from: from,
                to: to,
                value: value,
                gasUsed: gasUsed,
                gasPrice: gasPrice,
                timestamp: timestamp,
                blockNumber: blockNumber,
                status: .confirmed,
                contractAddress: isContractCall ? to : nil,
                tokenId: nil,
                tokenAmount: nil
            )
            
            entries.append(entry)
        }
        
        return entries
    }
    
    // MARK: - Cleanup
}

// MARK: - Errors

enum TransactionHistoryError: LocalizedError {
    case networkError(String)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
