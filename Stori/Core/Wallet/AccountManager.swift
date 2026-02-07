//
//  AccountManager.swift
//  Stori
//
//  Multi-account management for HD wallets
//  Derives multiple accounts from same seed using BIP-44 standard
//

import Foundation
import Observation
import BigInt

// MARK: - Derived Account

struct DerivedAccount: Identifiable, Codable {
    let id: UUID
    let index: Int
    let address: String
    var label: String
    let derivationPath: String
    var balance: BigUInt?
    var lastUsed: Date?
    
    init(index: Int, address: String, label: String? = nil, derivationPath: String) {
        self.id = UUID()
        self.index = index
        self.address = address
        self.label = label ?? "Account \(index + 1)"
        self.derivationPath = derivationPath
    }
    
    var shortAddress: String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
    
    var formattedBalance: String {
        guard let balance = balance else { return "—" }
        let tusValue = Double(balance) / 1e18
        if tusValue == 0 {
            return "0 TUS"
        } else if tusValue < 0.0001 {
            return "<0.0001 TUS"
        } else {
            return String(format: "%.4f TUS", tusValue)
        }
    }
}

// MARK: - Account Manager

@MainActor
@Observable
final class AccountManager {
    static let shared = AccountManager()
    
    private(set) var accounts: [DerivedAccount] = []
    private(set) var selectedAccountIndex: Int = 0
    private(set) var isLoadingBalances = false
    
    private let storageKey = "derivedAccounts"
    private let selectedIndexKey = "selectedAccountIndex"
    private let maxAccounts = 10
    
    private init() {
        loadFromStorage()
    }
    
    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when
    /// the runtime deinits this object on MainActor/task-local context.
    nonisolated deinit {}
    
    var selectedAccount: DerivedAccount? {
        guard selectedAccountIndex < accounts.count else { return nil }
        return accounts[selectedAccountIndex]
    }
    
    /// Generate additional accounts from the HD wallet
    func generateAccounts(from wallet: HDWallet, count: Int = 5) throws {
        guard count <= maxAccounts else {
            throw LocalWalletError.keyDerivationFailed("Cannot generate more than \(maxAccounts) accounts")
        }
        
        var newAccounts: [DerivedAccount] = []
        
        for i in 0..<count {
            let path = "m/44'/60'/0'/0/\(i)"
            let derivedWallet = try HDWallet.deriveAccount(from: wallet.getMnemonic(), index: i)
            let account = DerivedAccount(
                index: i,
                address: derivedWallet.address,
                label: i == 0 ? "Main Account" : "Account \(i + 1)",
                derivationPath: path
            )
            newAccounts.append(account)
        }
        
        accounts = newAccounts
        saveToStorage()
    }
    
    /// Select an account by index
    func selectAccount(at index: Int) {
        guard index < accounts.count else { return }
        selectedAccountIndex = index
        UserDefaults.standard.set(index, forKey: selectedIndexKey)
    }
    
    /// Update account label
    func updateLabel(for accountId: UUID, newLabel: String) {
        if let index = accounts.firstIndex(where: { $0.id == accountId }) {
            accounts[index].label = newLabel
            saveToStorage()
        }
    }
    
    /// Refresh balances for all accounts
    func refreshBalances(network: BlockchainNetwork) async {
        isLoadingBalances = true
        defer { isLoadingBalances = false }
        
        for i in 0..<accounts.count {
            do {
                let balance = try await fetchBalance(
                    address: accounts[i].address,
                    rpcURL: network.rpcURL
                )
                accounts[i].balance = balance
            } catch {
                accounts[i].balance = nil
            }
        }
        
        saveToStorage()
    }
    
    /// Mark account as used
    func markAccountAsUsed(at index: Int) {
        guard index < accounts.count else { return }
        accounts[index].lastUsed = Date()
        saveToStorage()
    }
    
    // MARK: - Storage
    
    private func saveToStorage() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadFromStorage() {
        // Load accounts
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DerivedAccount].self, from: data) {
            accounts = decoded
        }
        
        // Load selected index
        selectedAccountIndex = UserDefaults.standard.integer(forKey: selectedIndexKey)
    }
    
    // MARK: - Balance Fetching
    
    private func fetchBalance(address: String, rpcURL: URL) async throws -> BigUInt {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LocalWalletError.networkError("Failed to fetch balance")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw LocalWalletError.networkError("Invalid balance response")
        }
        
        let cleanHex = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
        guard let balance = BigUInt(cleanHex, radix: 16) else {
            throw LocalWalletError.networkError("Failed to parse balance")
        }
        
        return balance
    }
    
    // MARK: - Cleanup
}

// MARK: - HDWallet Extension

extension HDWallet {
    /// Derive a specific account from mnemonic
    static func deriveAccount(from mnemonic: [String], index: Int, language: MnemonicLanguage = .english, passphrase: String = "") throws -> HDWallet {
        let path = "m/44'/60'/0'/0/\(index)"
        return try HDWallet(
            mnemonic: mnemonic,
            language: language,
            passphrase: passphrase,
            derivationPath: path,
            importMethod: .mnemonicImport
        )
    }
}
