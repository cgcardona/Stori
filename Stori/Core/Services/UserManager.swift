//
//  UserManager.swift
//  Stori
//
//  Manages user identification and registration with the backend
//

import Foundation
import Observation

// MARK: - User Manager

@Observable
@MainActor
class UserManager {
    static let shared = UserManager()
    
    // MARK: - Observable Properties
    
    /// Current budget state
    var budget = BudgetState()
    
    /// Available AI models
    var availableModels: [AIModelInfo] = []
    
    /// Default model ID from backend
    var defaultModelId: String = ""
    
    /// Currently selected model ID (persisted)
    var selectedModelId: String {
        get {
            UserDefaults.standard.string(forKey: Keys.selectedModel) ?? defaultModelId
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.selectedModel)
        }
    }
    
    /// Privacy setting: store prompts for improvement
    var storePrompts: Bool {
        get {
            // Default to true (opt-in for improvement)
            UserDefaults.standard.object(forKey: Keys.storePrompts) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.storePrompts)
        }
    }
    
    /// Whether user is registered with backend
    var isRegistered: Bool {
        UserDefaults.standard.bool(forKey: Keys.isRegistered)
    }
    
    // MARK: - Private Properties
    
    @ObservationIgnored
    private let baseURL: String
    
    @ObservationIgnored
    private let session: URLSession
    
    // MARK: - Constants
    
    private enum Keys {
        static let userId = "stori_user_id"
        static let isRegistered = "stori_user_registered"
        static let selectedModel = "stori_selected_model"
        static let storePrompts = "stori_store_prompts"
    }
    
    // MARK: - Initialization
    
    private init() {
        #if DEBUG
        self.baseURL = "https://stage.example.com"
        #else
        self.baseURL = "https://api.example.com"  // Production URL
        #endif
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - User ID Management
    
    /// Get or create persistent user ID
    func getOrCreateUserId() -> String {
        if let existingId = UserDefaults.standard.string(forKey: Keys.userId) {
            return existingId
        }
        
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: Keys.userId)
        return newId
    }
    
    /// Get current user ID (nil if not set)
    var userId: String? {
        UserDefaults.standard.string(forKey: Keys.userId)
    }
    
    // MARK: - Registration
    
    /// Register user with backend (call on first launch)
    func registerUser() async throws -> UserRegistrationResponse {
        let userId = getOrCreateUserId()
        
        guard let url = URL(string: "\(baseURL)/api/v1/users/register") else {
            throw UserManagerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["user_id": userId]
        request.httpBody = try JSONEncoder().encode(body)
        
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UserManagerError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200, 201:
            let userResponse = try JSONDecoder().decode(UserRegistrationResponse.self, from: data)
            
            // Update local state
            budget = BudgetState(
                remaining: userResponse.budgetRemaining,
                limit: userResponse.budgetLimit,
                usageCount: userResponse.usageCount ?? 0
            )
            
            // Mark as registered
            UserDefaults.standard.set(true, forKey: Keys.isRegistered)
            
            return userResponse
            
        case 409:
            // User already exists - fetch their real budget
            UserDefaults.standard.set(true, forKey: Keys.isRegistered)
            
            // Fetch actual budget from /api/v1/users/me
            do {
                let userInfo = try await fetchUserInfo()
                return userInfo
            } catch {
                // Fallback to defaults if fetch fails
                return UserRegistrationResponse(
                    userId: userId,
                    budgetRemaining: 5.0,
                    budgetLimit: 5.0,
                    usageCount: 0,
                    createdAt: nil
                )
            }
            
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UserManagerError.registrationFailed(httpResponse.statusCode, errorBody)
        }
    }
    
    /// Fetch current user info (budget, usage count)
    func fetchUserInfo() async throws -> UserRegistrationResponse {
        guard let token = try? TokenManager.shared.getToken() else {
            throw UserManagerError.noToken
        }
        
        guard let url = URL(string: "\(baseURL)/api/v1/users/me") else {
            throw UserManagerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UserManagerError.fetchFailed
        }
        
        let userResponse = try JSONDecoder().decode(UserRegistrationResponse.self, from: data)
        
        // Update local state
        budget = BudgetState(
            remaining: userResponse.budgetRemaining,
            limit: userResponse.budgetLimit,
            usageCount: userResponse.usageCount ?? 0
        )
        
        return userResponse
    }
    
    /// Ensure user is registered (call before first compose)
    func ensureRegistered() async {
        guard !isRegistered else {
            // Fetch current budget from backend
            do {
                _ = try await fetchUserInfo()
            } catch {
            }
            return
        }
        
        do {
            _ = try await registerUser()
        } catch {
        }
    }
    
    // MARK: - Model Management
    
    /// Fetch available AI models from backend
    func fetchAvailableModels() async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/models") else {
            throw UserManagerError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UserManagerError.fetchFailed
        }
        
        let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
        
        availableModels = modelsResponse.models.sorted { $0.costPer1mInput < $1.costPer1mInput }
        defaultModelId = modelsResponse.defaultModel
        
        // If no model selected yet, prefer Claude 3.5 Sonnet
        if UserDefaults.standard.string(forKey: Keys.selectedModel) == nil {
            // Try to find Claude 3.5 Sonnet (check multiple variations)
            if let sonnet = availableModels.first(where: { 
                let id = $0.id.lowercased()
                let name = $0.name.lowercased()
                return (id.contains("sonnet") || name.contains("sonnet")) && 
                       (id.contains("3.5") || id.contains("3-5") || name.contains("3.5"))
            }) {
                selectedModelId = sonnet.id
            } else {
                selectedModelId = defaultModelId
            }
        }
        
    }
    
    /// Get currently selected model info
    var selectedModel: AIModelInfo? {
        availableModels.first { $0.id == selectedModelId }
    }
    
    // MARK: - Budget Updates
    
    /// Update budget from SSE event
    func updateBudget(from event: BudgetUpdateEvent) {
        budget.remaining = event.budgetRemaining
        budget.usageCount += 1
        
        
        // Post notification for other UI components
        NotificationCenter.default.post(
            name: .budgetUpdated,
            object: nil,
            userInfo: ["budget": budget]
        )
    }
    
    /// Update budget from response header
    func updateBudget(remaining: Double) {
        budget.remaining = remaining
    }
    
    /// Check if user has sufficient budget
    var hasBudget: Bool {
        budget.remaining > 0
    }
}

// MARK: - User Manager Errors

enum UserManagerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noToken
    case registrationFailed(Int, String)
    case fetchFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid server response"
        case .noToken:
            return "No access token available"
        case .registrationFailed(let code, let message):
            return "Registration failed (\(code)): \(message)"
        case .fetchFailed:
            return "Failed to fetch user information"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let budgetUpdated = Notification.Name("com.tellurstori.budgetUpdated")
    static let budgetExhausted = Notification.Name("com.tellurstori.budgetExhausted")
}
