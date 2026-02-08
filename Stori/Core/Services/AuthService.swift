//
//  AuthService.swift
//  Stori
//
//  JWT token validation service
//

import Foundation

// MARK: - Token Validation Response

struct TokenValidation: Codable {
    let valid: Bool
    let expiresAt: String
    let expiresInSeconds: Int
    let budgetRemaining: Double?
    let budgetLimit: Double?
    
    enum CodingKeys: String, CodingKey {
        case valid
        case expiresAt = "expires_at"
        case expiresInSeconds = "expires_in_seconds"
        case budgetRemaining = "budget_remaining"
        case budgetLimit = "budget_limit"
    }
    
    var expirationDate: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: expiresAt)
    }
    
    var isExpiringSoon: Bool {
        // Warn if less than 24 hours remaining
        return expiresInSeconds < 86400
    }
    
    /// Check if budget is available
    var hasBudget: Bool {
        guard let remaining = budgetRemaining else { return true }
        return remaining > 0
    }
    
    /// Budget warning level
    var budgetWarningLevel: BudgetState.WarningLevel {
        guard let remaining = budgetRemaining else { return .normal }
        if remaining <= 0 {
            return .exhausted
        } else if remaining < 0.25 {
            return .critical
        } else if remaining < 1.0 {
            return .low
        }
        return .normal
    }
}

// MARK: - Auth Service

@MainActor
@Observable
class AuthService {
    static let shared = AuthService()
    
    #if DEBUG
    let baseURL = "https://stage.example.com"
    #else
    let baseURL = "https://api.example.com"  // Production URL
    #endif
    
    private init() {}
    
    
    // MARK: - Public API
    
    /// Validate token with backend
    func validateToken(_ token: String) async throws -> TokenValidation {
        guard let url = URL(string: "\(baseURL)/api/v1/validate-token") else {
            throw AuthError.invalidURL
        }
        
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            
            switch httpResponse.statusCode {
            case 200:
                let validation = try JSONDecoder().decode(TokenValidation.self, from: data)
                return validation
            case 401:
                throw AuthError.tokenExpired
            default:
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                throw AuthError.serverError(httpResponse.statusCode)
            }
        } catch let urlError as URLError {
            throw AuthError.networkError(urlError)
        } catch {
            throw error
        }
    }
    
    /// Validate and save token (all-in-one authentication)
    func authenticateWithToken(_ token: String) async throws -> TokenValidation {
        // Validate with backend first
        let validation = try await validateToken(token)
        
        // If valid, save to Keychain
        try TokenManager.shared.saveToken(token)
        
        return validation
    }
    
    /// Check if stored token is still valid
    func checkStoredToken() async -> Bool {
        guard let token = try? TokenManager.shared.getToken() else {
            return false
        }
        
        do {
            _ = try await validateToken(token)
            return true
        } catch {
            // Token invalid, clear it
            try? TokenManager.shared.deleteToken()
            return false
        }
    }
    
    /// Validate stored token and return validation data
    func validateStoredToken() async -> TokenValidation? {
        guard let token = try? TokenManager.shared.getToken() else {
            return nil
        }
        
        do {
            let validation = try await validateToken(token)
            
            // Sync budget with UserManager
            await syncBudget(from: validation)
            
            return validation
        } catch {
            // Token invalid, clear it
            try? TokenManager.shared.deleteToken()
            return nil
        }
    }
    
    /// Sync budget information from token validation to UserManager
    @MainActor
    private func syncBudget(from validation: TokenValidation) {
        if let remaining = validation.budgetRemaining,
           let limit = validation.budgetLimit {
            UserManager.shared.budget = BudgetState(remaining: remaining, limit: limit)
        }
    }
    
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidURL
    case invalidResponse
    case tokenExpired
    case serverError(Int)
    case noToken
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid server response"
        case .tokenExpired:
            return "Your access code has expired. Please enter a new one."
        case .serverError(let code):
            return "Server error: \(code)"
        case .noToken:
            return "No access code found. Please enter your access code."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let tokenExpired = Notification.Name("com.tellurstori.tokenExpired")
    static let tokenValidated = Notification.Name("com.tellurstori.tokenValidated")
}
