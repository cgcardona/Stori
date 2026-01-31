//
//  ConversationModels.swift
//  Stori
//
//  Models for conversation history and chat interface
//

import Foundation

// MARK: - Conversation

struct Conversation: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ConversationMessage]
    var projectId: String? // Optional: nil = global conversation, not project-specific
    
    init(id: String = UUID().uuidString, title: String, createdAt: Date = Date(), updatedAt: Date = Date(), messages: [ConversationMessage] = [], projectId: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.projectId = projectId
    }
    
    // Convert from API response
    init(from detail: ConversationDetail) {
        self.id = detail.id
        self.title = detail.title
        self.createdAt = ISO8601DateFormatter().date(from: detail.createdAt) ?? Date()
        self.updatedAt = ISO8601DateFormatter().date(from: detail.updatedAt) ?? Date()
        self.messages = detail.messages.map { ConversationMessage(from: $0) }
        self.projectId = detail.projectId
    }
    
    // Convert from list item
    init(from item: ConversationListItem) {
        self.id = item.id
        self.title = item.title
        self.createdAt = ISO8601DateFormatter().date(from: item.createdAt) ?? Date()
        self.updatedAt = ISO8601DateFormatter().date(from: item.updatedAt) ?? Date()
        self.messages = []
        self.projectId = item.projectId
    }
    
    /// Preview of the first user message
    var preview: String {
        messages.first(where: { $0.role == .user })?.content ?? "New conversation"
    }
    
    /// Time since last update
    var timeAgo: String {
        let interval = Date().timeIntervalSince(updatedAt)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)
        
        if days > 0 {
            return "\(days)d ago"
        } else if hours > 0 {
            return "\(hours)h ago"
        } else if minutes > 0 {
            return "\(minutes)m ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: - Conversation Message

struct ConversationMessage: Identifiable, Codable, Equatable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    var actions: [MessageAction]  // Always present (empty array if none)
    var toolCalls: [ComposerToolCall]?  // Keep optional for now (legacy field)
    
    // Conversation replay fields (always present for assistant messages)
    let modelUsed: String?  // Optional: only present for assistant messages
    let tokensUsed: ConversationTokenUsage?  // Optional: only present for assistant messages
    let cost: Double  // Always present (0.0 for user messages)
    let sseEvents: [ConversationSSEEventModel]  // Always present (empty array if none)
    
    init(id: String = UUID().uuidString, role: MessageRole, content: String, timestamp: Date = Date(), actions: [MessageAction] = [], toolCalls: [ComposerToolCall]? = nil, modelUsed: String? = nil, tokensUsed: ConversationTokenUsage? = nil, cost: Double = 0.0, sseEvents: [ConversationSSEEventModel] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.actions = actions
        self.toolCalls = toolCalls
        self.modelUsed = modelUsed
        self.tokensUsed = tokensUsed
        self.cost = cost
        self.sseEvents = sseEvents
    }
    
    // Convert from API response
    init(from api: ConversationMessageAPI) {
        self.id = api.id
        self.role = MessageRole(rawValue: api.role) ?? .assistant
        self.content = api.content
        self.timestamp = ISO8601DateFormatter().date(from: api.timestamp) ?? Date()
        self.actions = api.actions?.map { MessageAction(from: $0) } ?? []
        self.toolCalls = nil // Tool calls handled separately
        self.modelUsed = api.modelUsed
        self.tokensUsed = api.tokensUsed != nil ? ConversationTokenUsage(from: api.tokensUsed!) : nil
        self.cost = api.cost
        self.sseEvents = api.sseEvents?.map { ConversationSSEEventModel(from: $0) } ?? []
    }
    
    enum MessageRole: String, Codable {
        case user
        case assistant
        case system
    }
    
    // Custom Equatable implementation (ignoring toolCalls as ComposerToolCall doesn't conform to Equatable)
    static func == (lhs: ConversationMessage, rhs: ConversationMessage) -> Bool {
        lhs.id == rhs.id
        // Note: Actions and sseEvents are compared as part of Codable synthesis
    }
    
    // Computed properties for replay UI
    var hasReplayData: Bool {
        return !sseEvents.isEmpty
    }
    
    var toolExecutionSummary: (succeeded: Int, failed: Int)? {
        guard !actions.isEmpty else { return nil }
        let succeeded = actions.filter { $0.success }.count
        let failed = actions.count - succeeded
        return (succeeded, failed)
    }
}

// MARK: - Message Action

struct MessageAction: Identifiable, Codable {
    let id: String
    let type: ActionType
    let description: String
    let success: Bool
    let errorMessage: String?  // Optional: only present on failure
    let timestamp: Date  // Always present
    let extraMetadata: ActionMetadata?  // Optional: only present for tool_execution type
    
    init(id: String = UUID().uuidString, type: ActionType, description: String, success: Bool, errorMessage: String? = nil, timestamp: Date = Date(), extraMetadata: ActionMetadata? = nil) {
        self.id = id
        self.type = type
        self.description = description
        self.success = success
        self.errorMessage = errorMessage
        self.timestamp = timestamp
        self.extraMetadata = extraMetadata
    }
    
    // Convert from API response
    init(from api: MessageActionAPI) {
        self.id = api.id
        self.type = ActionType(rawValue: api.actionType) ?? .projectModified
        self.description = api.description
        self.success = api.success
        self.errorMessage = api.errorMessage
        self.timestamp = ISO8601DateFormatter().date(from: api.timestamp ?? "") ?? Date()
        self.extraMetadata = api.extraMetadata != nil ? ActionMetadata(from: api.extraMetadata!) : nil
    }
    
    enum ActionType: String, Codable {
        case trackAdded = "track_added"
        case regionCreated = "region_created"
        case notesAdded = "notes_added"
        case effectAdded = "effect_added"
        case projectModified = "project_modified"
        case toolExecution = "tool_execution"
        case error
    }
    
    var icon: String {
        switch type {
        case .trackAdded: return "pianokeys"
        case .regionCreated: return "rectangle.stack"
        case .notesAdded: return "music.note.list"
        case .effectAdded: return "slider.horizontal.3"
        case .projectModified: return "doc.badge.gearshape"
        case .toolExecution: return "wrench.and.screwdriver"
        case .error: return "exclamationmark.triangle"
        }
    }
    
    // Duration formatted for display
    var durationString: String? {
        guard let duration = extraMetadata?.duration else { return nil }
        return String(format: "%.3fs", duration)
    }
    
    // Custom Equatable
    static func == (lhs: MessageAction, rhs: MessageAction) -> Bool {
        lhs.id == rhs.id
        // Note: Other fields compared as part of Codable synthesis
    }
}

// Make MessageAction Equatable
extension MessageAction: Equatable {}

// MARK: - Action Metadata

struct ActionMetadata: Codable {
    let toolName: String?
    let params: [String: AnyCodableValue]?
    let result: String?
    let startTime: Date?
    let endTime: Date?
    
    var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    // Convert from API response (dynamic JSON)
    init(from api: ActionMetadataAPI) {
        self.toolName = api.toolName
        self.params = api.params
        self.result = api.result
        self.startTime = api.startTime != nil ? ISO8601DateFormatter().date(from: api.startTime!) : nil
        self.endTime = api.endTime != nil ? ISO8601DateFormatter().date(from: api.endTime!) : nil
    }
    
    init(toolName: String? = nil, params: [String: AnyCodableValue]? = nil, result: String? = nil, startTime: Date? = nil, endTime: Date? = nil) {
        self.toolName = toolName
        self.params = params
        self.result = result
        self.startTime = startTime
        self.endTime = endTime
    }
    
    // Custom Equatable (skip params comparison due to AnyCodableValue complexity)
    static func == (lhs: ActionMetadata, rhs: ActionMetadata) -> Bool {
        lhs.toolName == rhs.toolName &&
        lhs.result == rhs.result &&
        lhs.startTime == rhs.startTime &&
        lhs.endTime == rhs.endTime
    }
}

// Make ActionMetadata Equatable
extension ActionMetadata: Equatable {}

// MARK: - SSE Event (for conversation replay)

struct ConversationSSEEventModel: Identifiable, Codable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(type)" }
    let type: String  // "tool_start", "tool_complete", "status", "state", etc.
    let data: [String: AnyCodableValue]
    let timestamp: Date
    
    init(type: String, data: [String: AnyCodableValue], timestamp: Date) {
        self.type = type
        self.data = data
        self.timestamp = timestamp
    }
    
    // Convert from API response
    init(from api: SSEEventAPI) {
        self.type = api.type
        self.data = api.data
        self.timestamp = ISO8601DateFormatter().date(from: api.timestamp) ?? Date()
    }
    
    // Helper computed properties for common data fields
    var statusMessage: String? {
        data["message"]?.stringValue
    }
    
    var stateName: String? {
        data["state"]?.stringValue
    }
    
    var toolName: String? {
        data["name"]?.stringValue
    }
    
    var content: String? {
        data["content"]?.stringValue
    }
    
    // Custom Equatable (skip data comparison due to AnyCodableValue complexity)
    static func == (lhs: ConversationSSEEventModel, rhs: ConversationSSEEventModel) -> Bool {
        lhs.type == rhs.type &&
        lhs.timestamp == rhs.timestamp
    }
}

// Make ConversationSSEEventModel Equatable
extension ConversationSSEEventModel: Equatable {}

// MARK: - Token Usage

struct ConversationTokenUsage: Codable, Equatable {
    let prompt: Int
    let completion: Int
    
    var total: Int {
        prompt + completion
    }
    
    // Convert from API response
    init(from api: TokenUsageAPI) {
        self.prompt = api.prompt
        self.completion = api.completion
    }
    
    init(prompt: Int, completion: Int) {
        self.prompt = prompt
        self.completion = completion
    }
}

// MARK: - Budget Details

struct BudgetDetails {
    let remaining: Double
    let limit: Double
    let usageCount: Int
    let averageCostPerRequest: Double
    let estimatedRequestsRemaining: Int
    let resetDate: Date?
    
    var percentUsed: Double {
        guard limit > 0 else { return 0 }
        return ((limit - remaining) / limit) * 100
    }
    
    var formattedResetDate: String {
        guard let resetDate = resetDate else { return "No reset scheduled" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Resets \(formatter.string(from: resetDate))"
    }
}
