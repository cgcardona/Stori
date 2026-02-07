//
//  WalletService.swift
//  Stori
//
//  Global wallet service for managing wallet state throughout the app
//

import Foundation
import SwiftUI
import Combine
import BigInt
import CryptoSwift
import Web3
import Observation

// MARK: - Wallet Service

/// Singleton wallet service accessible throughout the app
/// Manages wallet creation, import, unlocking, and transaction signing
@MainActor
@Observable
final class WalletService {
    
    // MARK: - Singleton
    
    static let shared = WalletService()
    
    // MARK: - Observable State
    
    /// The active wallet (nil if no wallet or locked)
    private(set) var wallet: (any WalletProtocol)?
    
    /// Whether the wallet is currently unlocked
    private(set) var isUnlocked = false
    
    /// Selected blockchain network
    var selectedNetwork: BlockchainNetwork = .tellUrStoriLocal
    
    /// Current TUS balance (in wei)
    private(set) var balance: BigUInt = 0
    
    /// Whether we're currently loading the balance
    private(set) var isLoadingBalance = false
    
    /// Last error message
    private(set) var lastError: String?
    
    // MARK: - Computed Properties
    
    /// Whether a wallet exists (stored in keychain)
    var hasWallet: Bool {
        SecureKeyStorage.shared.hasStoredWallet
    }
    
    /// The wallet's address (if unlocked)
    var address: String? {
        wallet?.address
    }
    
    /// Shortened address for display
    var shortAddress: String? {
        guard let addr = address else { return nil }
        guard addr.count > 10 else { return addr }
        return "\(addr.prefix(6))...\(addr.suffix(4))"
    }
    
    /// Formatted balance in TUS
    var formattedBalance: String {
        let tusValue = Double(balance) / 1e18
        if tusValue == 0 {
            return "0 TUS"
        } else if tusValue < 0.0001 {
            return "<0.0001 TUS"
        } else {
            return String(format: "%.4f TUS", tusValue)
        }
    }
    
    // SECURITY: Dev key detection removed - no hardcoded keys in codebase
    
    // MARK: - Initialization
    
    private init() {
        // Load saved network preference
        if let savedNetwork = UserDefaults.standard.string(forKey: "selectedNetwork"),
           let network = BlockchainNetwork(rawValue: savedNetwork) {
            selectedNetwork = network
        }
    }
    
    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when
    /// the runtime deinits this object on MainActor/task-local context.
    nonisolated deinit {}
    
    // MARK: - Wallet Creation
    
    /// Create a new HD wallet with a generated mnemonic
    /// - Parameters:
    ///   - strength: Mnemonic strength (default: 24 words)
    ///   - language: Mnemonic language
    ///   - passphrase: Optional BIP-39 passphrase
    ///   - password: Password for keychain encryption
    ///   - security: Security level for storage
    /// - Returns: The generated mnemonic words (for backup display)
    func createWallet(
        strength: MnemonicStrength = .words24,
        language: MnemonicLanguage = .english,
        passphrase: String = "",
        password: String,
        security: WalletSecurityLevel = .biometric
    ) async throws -> [String] {
        // Create HD wallet
        let hdWallet = try HDWallet.create(
            strength: strength,
            language: language,
            passphrase: passphrase
        )
        
        let mnemonic = hdWallet.getMnemonic()
        
        // Store in keychain
        try await SecureKeyStorage.shared.storeMnemonic(
            mnemonic,
            password: password,
            security: security
        )
        
        // Set as active wallet
        self.wallet = hdWallet
        self.isUnlocked = true
        self.lastError = nil
        
        // Fetch initial balance
        await refreshBalance()
        
        return mnemonic
    }
    
    /// Import a wallet from mnemonic
    /// - Parameters:
    ///   - mnemonic: Array of mnemonic words
    ///   - language: Mnemonic language for validation
    ///   - passphrase: Optional BIP-39 passphrase
    ///   - password: Password for keychain encryption
    ///   - security: Security level for storage
    func importMnemonic(
        _ mnemonic: [String],
        language: MnemonicLanguage = .english,
        passphrase: String = "",
        password: String,
        security: WalletSecurityLevel = .biometric
    ) async throws {
        // Create HD wallet from mnemonic
        let hdWallet = try HDWallet(
            mnemonic: mnemonic,
            language: language,
            passphrase: passphrase,
            importMethod: .mnemonicImport
        )
        
        // Store in keychain
        try await SecureKeyStorage.shared.storeMnemonic(
            mnemonic,
            password: password,
            security: security
        )
        
        // Set as active wallet
        self.wallet = hdWallet
        self.isUnlocked = true
        self.lastError = nil
        
        // Fetch initial balance
        await refreshBalance()
    }
    
    /// Import a wallet from private key (for dev/testing)
    /// - Parameters:
    ///   - privateKey: Raw private key data or hex string
    ///   - password: Password for keychain encryption
    ///   - security: Security level for storage
    func importPrivateKey(
        _ privateKey: String,
        password: String,
        security: WalletSecurityLevel = .biometric
    ) async throws {
        // Parse and validate private key
        let keyData = try PrivateKeyParser.parse(privateKey)
        
        // Create simple wallet
        let simpleWallet = try SimpleWallet(privateKey: keyData)
        
        // Store in keychain
        try await SecureKeyStorage.shared.storePrivateKey(
            keyData,
            password: password,
            security: security
        )
        
        // Set as active wallet
        self.wallet = simpleWallet
        self.isUnlocked = true
        self.lastError = nil
        
        // Fetch initial balance
        await refreshBalance()
    }
    
    // MARK: - Wallet Unlock/Lock
    
    /// Unlock the wallet with password
    /// - Parameter password: User's password
    func unlock(password: String) async throws {
        // Run heavy crypto work on background thread to avoid blocking UI
        let newWallet: any WalletProtocol = try await Task.detached(priority: .userInitiated) {
            guard let metadata = try SecureKeyStorage.shared.getMetadata() else {
                throw LocalWalletError.walletNotFound
            }
            
            if metadata.isHDWallet {
                // Retrieve and restore HD wallet
                let mnemonic = try await SecureKeyStorage.shared.retrieveMnemonic(password: password)
                return try HDWallet(mnemonic: mnemonic, importMethod: .mnemonicImport)
            } else {
                // Retrieve and restore simple wallet
                let keyData = try await SecureKeyStorage.shared.retrievePrivateKey(password: password)
                return try SimpleWallet(privateKey: keyData)
            }
        }.value
        
        // Update state on main thread
        await MainActor.run {
            self.wallet = newWallet
            self.isUnlocked = true
            self.lastError = nil
        }
        
        // Fetch balance
        await refreshBalance()
    }
    
    /// Lock the wallet (clear from memory)
    func lock() {
        self.wallet = nil
        self.isUnlocked = false
        self.balance = 0
    }
    
    /// Delete the wallet entirely
    /// WARNING: This is irreversible!
    func deleteWallet() throws {
        lock()
        try SecureKeyStorage.shared.deleteWallet()
        // @Observable automatically tracks property changes - no manual notification needed
    }
    
    #if DEBUG
    /// Development-only unlock with empty password
    /// SECURITY: Only for DEBUG builds - requires explicit password in production
    func unlockDev() async throws {
        // Check if we have a stored wallet first
        guard let metadata = try? SecureKeyStorage.shared.getMetadata() else {
            throw LocalWalletError.walletNotFound
        }
        
        // Try unlocking with empty password (common for dev wallets)
        let devPassword = ""
        
        do {
            if metadata.isHDWallet {
                let mnemonic = try await SecureKeyStorage.shared.retrieveMnemonic(password: devPassword)
                let hdWallet = try HDWallet(mnemonic: mnemonic, importMethod: .mnemonicImport)
                self.wallet = hdWallet
            } else {
                let keyData = try await SecureKeyStorage.shared.retrievePrivateKey(password: devPassword)
                let simpleWallet = try SimpleWallet(privateKey: keyData)
                self.wallet = simpleWallet
            }
            
            self.isUnlocked = true
            self.lastError = nil
            await refreshBalance()
        } catch {
            throw LocalWalletError.passwordIncorrect
        }
    }
    #endif
    
    // MARK: - Transaction Signing
    
    /// Sign a message hash
    /// - Parameter hash: 32-byte message hash
    /// - Returns: Signature data
    func signHash(_ hash: Data) throws -> Data {
        guard let wallet = wallet else {
            throw LocalWalletError.walletLocked
        }
        return try wallet.signHash(hash)
    }
    
    /// Sign a message (will be hashed first)
    /// - Parameter message: Message to sign
    /// - Returns: Signature data
    func signMessage(_ message: String) throws -> Data {
        guard let messageData = message.data(using: .utf8) else {
            throw LocalWalletError.signingFailed("Failed to encode message")
        }
        
        // Ethereum signed message format
        let prefix = "\u{19}Ethereum Signed Message:\n\(messageData.count)"
        var prefixedMessage = Data(prefix.utf8)
        prefixedMessage.append(messageData)
        
        // Hash with Keccak256
        let hash = prefixedMessage.sha3(.keccak256)
        
        return try signHash(Data(hash))
    }
    
    /// Get the private key for transaction building
    /// WARNING: Use with extreme caution!
    func getPrivateKey() throws -> Data {
        guard let wallet = wallet else {
            throw LocalWalletError.walletLocked
        }
        return try wallet.getPrivateKey()
    }
    
    // MARK: - Transaction Signing (EIP-155/712)
    
    /// Get transaction signer for the current wallet
    func getTransactionSigner() throws -> TransactionSigner {
        guard let wallet = wallet else {
            throw LocalWalletError.walletLocked
        }
        return TransactionSigner(wallet: wallet)
    }
    
    /// Sign and return a legacy transaction (EIP-155)
    func signTransaction(_ transaction: EthereumTransaction) throws -> SignedTransaction {
        let signer = try getTransactionSigner()
        return try signer.signTransaction(transaction)
    }
    
    /// Sign and return an EIP-1559 transaction
    func signEIP1559Transaction(_ transaction: EIP1559Transaction) throws -> SignedTransaction {
        let signer = try getTransactionSigner()
        return try signer.signEIP1559Transaction(transaction)
    }
    
    /// Sign EIP-712 typed data
    func signTypedData(_ typedData: EIP712TypedData) throws -> Data {
        let signer = try getTransactionSigner()
        return try signer.signTypedData(typedData)
    }
    
    /// Get the current nonce for the wallet address
    func getNonce() async throws -> BigUInt {
        guard let address = address else {
            throw LocalWalletError.walletLocked
        }
        return try await fetchNonce(address: address)
    }
    
    /// Fetch nonce from RPC
    /// Fetch the current nonce for an address (public method)
    func fetchNonce(address: String) async throws -> BigUInt {
        let rpcURL = selectedNetwork.rpcURL
        
        
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionCount",
            "params": [address, "pending"],
            "id": 1
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Log raw response
        if let responseStr = String(data: data, encoding: .utf8) {
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultHex = json["result"] as? String else {
            throw LocalWalletError.networkError("Failed to parse nonce response")
        }
        
        let hex = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        guard let nonce = BigUInt(hex, radix: 16) else {
            throw LocalWalletError.networkError("Invalid nonce format")
        }
        
        return nonce
    }
    
    /// Send a signed transaction to the network
    func sendTransaction(_ signedTx: SignedTransaction) async throws -> String {
        let rpcURL = selectedNetwork.rpcURL
        
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [signedTx.rawTransactionHex],
            "id": 1
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalWalletError.networkError("Failed to parse response")
        }
        
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw LocalWalletError.networkError("Transaction failed: \(message)")
        }
        
        guard let txHash = json["result"] as? String else {
            throw LocalWalletError.networkError("No transaction hash returned")
        }
        
        return txHash
    }
    
    /// Send a raw signed transaction (as Data) to the network
    func sendSignedTransaction(_ rawTx: Data) async throws -> String {
        let rpcURL = selectedNetwork.rpcURL
        
        
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let hexTx = "0x" + rawTx.map { String(format: "%02x", $0) }.joined()
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [hexTx],
            "id": 1
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Log raw response
        if let responseStr = String(data: data, encoding: .utf8) {
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalWalletError.networkError("Failed to parse response")
        }
        
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            if let errorCode = error["code"] {
            }
            throw LocalWalletError.networkError("Transaction failed: \(message)")
        }
        
        guard let txHash = json["result"] as? String else {
            throw LocalWalletError.networkError("No transaction hash returned")
        }
        
        return txHash
    }
    
    /// Create, sign, and send a TUS transfer
    func sendTUS(to: String, amount: BigUInt) async throws -> String {
        let nonce = try await getNonce()
        
        let transaction = EthereumTransaction.transfer(
            to: to,
            value: amount,
            nonce: nonce,
            chainId: BigUInt(selectedNetwork.chainId)
        )
        
        let signedTx = try signTransaction(transaction)
        return try await sendTransaction(signedTx)
    }
    
    // MARK: - Balance
    
    /// Refresh the wallet balance
    func refreshBalance() async {
        guard let address = address else { return }
        
        isLoadingBalance = true
        defer { isLoadingBalance = false }
        
        do {
            let balanceWei = try await fetchBalance(address: address)
            self.balance = balanceWei
        } catch {
            #if DEBUG
            // Use mock balance in development when RPC is unavailable
            // 1,234.56 TUS in wei (1e18 base)
            self.balance = BigUInt(stringLiteral: "1234560000000000000000")
            self.lastError = nil
            #else
            self.lastError = "Failed to fetch balance: \(error.localizedDescription)"
            #endif
        }
    }
    
    /// Fetch balance from RPC
    private func fetchBalance(address: String) async throws -> BigUInt {
        let rpcURL = selectedNetwork.rpcURL
        
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
        
        // Parse hex balance
        let cleanHex = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
        guard let balance = BigUInt(cleanHex, radix: 16) else {
            throw LocalWalletError.networkError("Failed to parse balance")
        }
        
        return balance
    }
    
    // MARK: - Network
    
    /// Switch to a different network
    func switchNetwork(_ network: BlockchainNetwork) async {
        selectedNetwork = network
        UserDefaults.standard.set(network.rawValue, forKey: "selectedNetwork")
        
        // Refresh balance for new network
        await refreshBalance()
    }
    
    // MARK: - Backup
    
    /// Get mnemonic for backup (requires password)
    /// - Parameter password: User's password
    /// - Returns: Mnemonic words
    func getMnemonicForBackup(password: String) async throws -> [String] {
        guard let metadata = try SecureKeyStorage.shared.getMetadata(),
              metadata.isHDWallet else {
            throw LocalWalletError.invalidMnemonic("Not an HD wallet")
        }
        
        return try await SecureKeyStorage.shared.retrieveMnemonic(password: password)
    }
    
    // MARK: - Cleanup
}

// MARK: - Notification Names

extension Notification.Name {
    static let walletStateChanged = Notification.Name("walletStateChanged")
    static let walletBalanceUpdated = Notification.Name("walletBalanceUpdated")
}
