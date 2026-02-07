//
//  TokenManager.swift
//  Stori
//
//  Secure JWT token storage using macOS Keychain
//

import Security
import Foundation

@Observable
class TokenManager {
    static let shared = TokenManager()
    
    private let service = "com.tellurstori.stori"
    private let account = "access_token"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Save token to Keychain
    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        
        // Delete existing token if any
        try? deleteToken()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenError.saveFailed
        }
    }
    
    /// Retrieve token from Keychain
    func getToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw TokenError.notFound
        }
        
        return token
    }
    
    /// Delete token from Keychain
    func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenError.deleteFailed
        }
    }
    
    /// Check if token exists in Keychain
    var hasToken: Bool {
        return (try? getToken()) != nil
    }
    
    // CRITICAL: Protective deinit for @Observable class (ASan Issue #84742+)
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
    // No async resources owned.
    // No deinit required.
}

// MARK: - Token Errors

enum TokenError: LocalizedError {
    case saveFailed
    case notFound
    case deleteFailed
    
    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Failed to save access code securely"
        case .notFound:
            return "No access code found"
        case .deleteFailed:
            return "Failed to delete access code"
        }
    }
}
