//
//  BudgetModels.swift
//  Stori
//
//  Models for budget tracking and model selection
//

import Foundation

// MARK: - User Registration Response

struct UserRegistrationResponse: Codable {
    let userId: String
    let budgetRemaining: Double
    let budgetLimit: Double
    let usageCount: Int?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case budgetRemaining = "budget_remaining"
        case budgetLimit = "budget_limit"
        case usageCount = "usage_count"
        case createdAt = "created_at"
    }
}

// MARK: - Model Information

struct AIModelInfo: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let costPer1mInput: Double
    let costPer1mOutput: Double
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case costPer1mInput = "cost_per_1m_input"
        case costPer1mOutput = "cost_per_1m_output"
    }
    
    /// Display cost string (uses input cost as primary indicator)
    var displayCost: String {
        if costPer1mInput < 0.10 {
            return String(format: "$%.3f/1M", costPer1mInput)
        }
        return String(format: "$%.2f/1M", costPer1mInput)
    }
    
    /// Model description based on ID
    var description: String {
        let lowercaseId = id.lowercased()
        let lowercaseName = name.lowercased()
        
        if lowercaseId.contains("opus") || lowercaseName.contains("opus") {
            return "Anthropic's most capable model for complex tasks"
        } else if lowercaseId.contains("sonnet") || lowercaseName.contains("sonnet") {
            return "Balanced performance and speed for most tasks"
        } else if lowercaseId.contains("haiku") || lowercaseName.contains("haiku") {
            return "Fast and cost-effective for simple tasks"
        } else if lowercaseId.contains("gpt-4") || lowercaseName.contains("gpt-4") {
            return "OpenAI's most advanced reasoning model"
        } else if lowercaseId.contains("gpt-3.5") {
            return "Fast and efficient for straightforward tasks"
        } else if lowercaseId.contains("gemini") && (lowercaseId.contains("pro") || lowercaseName.contains("pro")) {
            return "Google's advanced multimodal model"
        } else if lowercaseId.contains("gemini") && lowercaseId.contains("flash") {
            return "Fast and versatile for most use cases"
        } else if lowercaseId.contains("llama") {
            return "Meta's open-source language model"
        }
        return "High-quality AI model for music creation"
    }
    
    /// Context window size
    var contextWindow: String {
        let lowercaseId = id.lowercased()
        let lowercaseName = name.lowercased()
        
        if lowercaseId.contains("opus") || lowercaseId.contains("sonnet") || lowercaseId.contains("haiku") {
            return "200k"
        } else if lowercaseId.contains("gpt-4") {
            return "128k"
        } else if lowercaseId.contains("gpt-3.5-turbo") {
            return "16k"
        } else if lowercaseId.contains("gemini") && (lowercaseId.contains("pro") || lowercaseName.contains("pro")) {
            return "2M"
        } else if lowercaseId.contains("gemini") {
            return "1M"
        } else if lowercaseId.contains("llama") {
            return "128k"
        }
        return "Context varies"
    }
    
    /// Speed indicator
    var speed: String {
        let lowercaseId = id.lowercased()
        let lowercaseName = name.lowercased()
        
        if lowercaseId.contains("haiku") || lowercaseId.contains("flash") || lowercaseId.contains("gpt-3.5") {
            return "Fast"
        } else if lowercaseId.contains("sonnet") {
            return "Balanced"
        } else if lowercaseId.contains("opus") || lowercaseId.contains("gpt-4") {
            return "Thorough"
        }
        return "Standard"
    }
    
    /// Whether model has extended thinking/reasoning capability
    var hasThinking: Bool {
        let lowercaseId = id.lowercased()
        let lowercaseName = name.lowercased()
        
        // Models with explicit thinking/reasoning modes
        return lowercaseId.contains("opus") || 
               lowercaseId.contains("gpt-4") ||
               lowercaseId.contains("o1") ||
               lowercaseId.contains("o3") ||
               (lowercaseId.contains("sonnet") && (lowercaseId.contains("3.5") || lowercaseId.contains("3.7")))
    }
    
    /// Reasoning effort description
    var reasoningEffort: String? {
        let lowercaseId = id.lowercased()
        
        if lowercaseId.contains("opus") {
            return "high effort"
        } else if lowercaseId.contains("sonnet") && (lowercaseId.contains("3.5") || lowercaseId.contains("3.7")) {
            return "medium effort"
        } else if lowercaseId.contains("gpt-4") {
            return "medium reasoning effort"
        } else if lowercaseId.contains("o1") || lowercaseId.contains("o3") {
            return "deep reasoning"
        }
        return nil
    }
    
    /// Cost tier for UI categorization
    var costTier: CostTier {
        if costPer1mInput < 0.20 {
            return .budget
        } else if costPer1mInput < 1.0 {
            return .standard
        } else if costPer1mInput < 5.0 {
            return .premium
        } else {
            return .enterprise
        }
    }
    
    enum CostTier: String {
        case budget = "Budget"
        case standard = "Standard"
        case premium = "Premium"
        case enterprise = "Enterprise"
    }
}

// MARK: - Models List Response

struct ModelsResponse: Codable {
    let models: [AIModelInfo]
    let defaultModel: String
    
    enum CodingKeys: String, CodingKey {
        case models
        case defaultModel = "default_model"
    }
}

// MARK: - Budget Update Event (from SSE)

struct BudgetUpdateEvent: Codable {
    let type: String
    let budgetRemaining: Double
    let cost: Double
    let tokens: TokenUsage
    
    struct TokenUsage: Codable {
        let prompt: Int
        let completion: Int
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case budgetRemaining = "budget_remaining"
        case cost
        case tokens
    }
}

// MARK: - Budget Error Response (402 Payment Required)

struct BudgetExhaustedError: Codable {
    let detail: BudgetErrorDetail
    
    struct BudgetErrorDetail: Codable {
        let error: String
        let budgetRemaining: Double
        let message: String
        
        enum CodingKeys: String, CodingKey {
            case error
            case budgetRemaining = "budget_remaining"
            case message
        }
    }
}

// MARK: - User Budget State

/// Observable budget state for UI binding
struct BudgetState {
    var remaining: Double
    var limit: Double
    var usageCount: Int
    
    init(remaining: Double = 5.0, limit: Double = 5.0, usageCount: Int = 0) {
        self.remaining = remaining
        self.limit = limit
        self.usageCount = usageCount
    }
    
    /// Budget as percentage (0.0 to 1.0)
    var percentRemaining: Double {
        guard limit > 0 else { return 0 }
        return remaining / limit
    }
    
    /// Formatted remaining amount
    var formattedRemaining: String {
        String(format: "$%.2f", remaining)
    }
    
    /// Formatted limit amount
    var formattedLimit: String {
        String(format: "$%.2f", limit)
    }
    
    /// Display string like "$4.23 / $5.00"
    var displayString: String {
        "\(formattedRemaining) / \(formattedLimit)"
    }
    
    /// Warning level for UI coloring
    var warningLevel: WarningLevel {
        if remaining <= 0 {
            return .exhausted
        } else if remaining < 0.25 {
            return .critical
        } else if remaining < 1.0 {
            return .low
        } else {
            return .normal
        }
    }
    
    enum WarningLevel {
        case normal, low, critical, exhausted
    }
}

// MARK: - Compose Request with Model Selection

/// Extended compose request with model selection and privacy options
struct ExtendedComposeRequest: Codable {
    let mode: String
    let prompt: String
    let project: ProjectContext?
    let model: String?
    let storePrompt: Bool
    
    enum CodingKeys: String, CodingKey {
        case mode, prompt, project, model
        case storePrompt = "store_prompt"
    }
    
    init(mode: String, prompt: String, project: ProjectContext?, model: String? = nil, storePrompt: Bool = true) {
        self.mode = mode
        self.prompt = prompt
        self.project = project
        self.model = model
        self.storePrompt = storePrompt
    }
}
