//
//  ConversationService.swift
//  Stori
//
//  Service for managing conversation history with backend
//

import Foundation

// MARK: - Conversation Service

@Observable
@MainActor
final class ConversationService {
    static let shared = ConversationService()
    
    private let baseURL: String
    
    private init() {
        #if DEBUG
        self.baseURL = "https://stage.example.com/api/v1"
        #else
        self.baseURL = "https://stage.example.com/api/v1"
        #endif
    }
    
    
    // MARK: - API Requests
    
    private func makeRequest(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> URLRequest {
        var components = URLComponents(string: "\(baseURL)\(endpoint)")!
        components.queryItems = queryItems
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        
        // Get token from TokenManager
        if let token = try? TokenManager.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        return request
    }
    
    // MARK: - Create Conversation
    
    func createConversation(title: String = "New Conversation", projectId: String, projectContext: ProjectContextRequest? = nil) async throws -> ConversationDetail {
        let body = CreateConversationRequest(title: title, projectId: projectId, project_context: projectContext)
        let request = try await makeRequest(endpoint: "/conversations", method: "POST", body: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConversationError.invalidResponse
        }
        
        guard httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No body"
            throw ConversationError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ConversationDetail.self, from: data)
    }
    
    // MARK: - List Conversations
    
    func listConversations(projectId: String, limit: Int = 50, offset: Int = 0, includeArchived: Bool = false) async throws -> ConversationListResponse {
        let queryItems = [
            URLQueryItem(name: "project_id", value: projectId),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "include_archived", value: includeArchived ? "true" : "false")
        ]
        
        let request = try await makeRequest(endpoint: "/conversations", queryItems: queryItems)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConversationError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No body"
            
            // Handle specific errors
            if httpResponse.statusCode == 401 {
                throw ConversationError.unauthorized
            }
            throw ConversationError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ConversationListResponse.self, from: data)
    }
    
    // MARK: - Get Conversation with Full History
    
    func getConversation(id: String) async throws -> ConversationDetail {
        let request = try await makeRequest(endpoint: "/conversations/\(id)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConversationError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            throw ConversationError.notFound
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ConversationError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConversationDetail.self, from: data)
    }
    
    // MARK: - Send Message (SSE Streaming)
    
    func sendMessage(
        conversationId: String,
        prompt: String,
        model: String? = nil,
        storePrompt: Bool = true,
        onEvent: @escaping (ConversationSSEEvent) -> Void
    ) async throws {
        let body = SendMessageRequest(
            prompt: prompt,
            model: model,
            project: nil, // TODO: Add project context
            store_prompt: storePrompt
        )
        
        let request = try await makeRequest(endpoint: "/conversations/\(conversationId)/messages", method: "POST", body: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConversationError.invalidResponse
        }
        
        if httpResponse.statusCode == 402 {
            throw ConversationError.insufficientBudget
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ConversationError.httpError(httpResponse.statusCode)
        }
        
        // Parse SSE stream
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                
                guard let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else {
                    continue
                }
                
                #if DEBUG
                if let message = json["message"] as? String {
                }
                if let content = json["content"] as? String {
                }
                if let state = json["state"] as? String {
                }
                #endif
                
                await MainActor.run {
                    switch type {
                    case "status":
                        if let message = json["message"] as? String {
                            onEvent(ConversationSSEEvent.status(message))
                        }
                    
                    case "state":
                        if let state = json["state"] as? String {
                            onEvent(ConversationSSEEvent.state(state))
                        }
                        
                    case "thinking_delta":
                        if let content = json["content"] as? String {
                            onEvent(ConversationSSEEvent.thinkingDelta(content))
                        }
                        
                    case "content":
                        if let content = json["content"] as? String {
                            onEvent(ConversationSSEEvent.content(content))
                        }
                    
                    case "tool_start":
                        if let name = json["name"] as? String {
                            onEvent(ConversationSSEEvent.toolStart(name))
                        }
                        
                    case "tool_call":
                        if let data = jsonString.data(using: .utf8),
                           let toolCall = try? JSONDecoder().decode(ToolCallEvent.self, from: data) {
                            onEvent(ConversationSSEEvent.toolCall(toolCall))
                        }
                        
                    case "tool_complete":
                        if let name = json["name"] as? String,
                           let successInt = json["success"] as? Int {
                            let success = successInt == 1
                            let toolResult = ToolResultEvent(
                                type: "tool_complete",
                                tool: name,
                                result: success ? "✅ \(name)" : "❌ \(name) failed",
                                success: success
                            )
                            onEvent(ConversationSSEEvent.toolComplete(toolResult))
                        }
                    
                    case "tool_error":
                        if let name = json["name"] as? String,
                           let error = json["error"] as? String {
                            onEvent(ConversationSSEEvent.toolError("\(name): \(error)"))
                        }
                        
                    case "budget_update":
                        if let remaining = json["budget_remaining"] as? Double {
                            let cost = json["cost"] as? Double ?? 0.0
                            let update = BudgetUpdateSSE(budget_remaining: remaining, cost: cost)
                            onEvent(ConversationSSEEvent.budgetUpdate(update))
                        }
                        
                    case "complete":
                        onEvent(ConversationSSEEvent.complete)
                        
                    case "error":
                        if let error = json["error"] as? String {
                            onEvent(ConversationSSEEvent.error(error))
                        }
                        
                    default:
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Update Title
    
    func updateTitle(conversationId: String, newTitle: String) async throws {
        let body = UpdateTitleRequest(title: newTitle)
        let request = try await makeRequest(endpoint: "/conversations/\(conversationId)", method: "PATCH", body: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ConversationError.invalidResponse
        }
    }
    
    // MARK: - Archive Conversation
    
    func archiveConversation(id: String) async throws {
        let request = try await makeRequest(endpoint: "/conversations/\(id)", method: "DELETE")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 else {
            throw ConversationError.invalidResponse
        }
    }
    
    // MARK: - Delete Conversation (Permanent)
    
    func deleteConversation(id: String) async throws {
        let queryItems = [URLQueryItem(name: "hard_delete", value: "true")]
        let request = try await makeRequest(endpoint: "/conversations/\(id)", method: "DELETE", queryItems: queryItems)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 else {
            throw ConversationError.invalidResponse
        }
    }
    
    // MARK: - Search Conversations
    
    func searchConversations(query: String, limit: Int = 20) async throws -> SearchResponse {
        let queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        let request = try await makeRequest(endpoint: "/conversations/search", queryItems: queryItems)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ConversationError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SearchResponse.self, from: data)
    }
    
    // MARK: - Cleanup
}

// MARK: - Request Models

struct CreateConversationRequest: Codable {
    let title: String
    let projectId: String  // Required: conversations must be linked to projects
    let project_context: ProjectContextRequest?
    
    enum CodingKeys: String, CodingKey {
        case title
        case projectId = "project_id"
        case project_context
    }
}

struct ProjectContextRequest: Codable {
    let tempo: Int?
    let key: String?
    let time_signature: String?
}

struct SendMessageRequest: Codable {
    let prompt: String
    let model: String?
    let project: ProjectContextRequest?
    let store_prompt: Bool
}

struct UpdateTitleRequest: Codable {
    let title: String
}

// MARK: - Response Models

struct ConversationListResponse: Codable {
    let conversations: [ConversationListItem]
    let total: Int
    let limit: Int
    let offset: Int
}

struct ConversationListItem: Codable, Identifiable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
    let isArchived: Bool
    let messageCount: Int
    let preview: String
    let projectId: String? // Optional: conversations can be global (no project) or project-specific
    // Using decoder.keyDecodingStrategy = .convertFromSnakeCase, so no CodingKeys needed
}

struct ConversationDetail: Codable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
    let isArchived: Bool
    let projectId: String? // Optional: conversations can be global (no project) or project-specific
    let projectContext: ProjectContextRequest?
    let messages: [ConversationMessageAPI]
    // Using decoder.keyDecodingStrategy = .convertFromSnakeCase, so no CodingKeys needed
}

struct ConversationMessageAPI: Codable, Identifiable {
    let id: String
    let role: String
    let content: String
    let timestamp: String
    let modelUsed: String?
    let tokensUsed: TokenUsageAPI?
    let cost: Double
    let toolCalls: [ToolCallAPI]?
    let actions: [MessageActionAPI]?
    let sseEvents: [SSEEventAPI]?  // NEW: SSE event stream for replay
    // Using decoder.keyDecodingStrategy = .convertFromSnakeCase, so no CodingKeys needed
}

struct TokenUsageAPI: Codable {
    let prompt: Int
    let completion: Int
}

struct ToolCallAPI: Codable {
    let type: String
    let name: String
    let arguments: [String: AnyCodableValue]?  // Flexible typing: supports strings, numbers, arrays, nested objects
}

struct MessageActionAPI: Codable, Identifiable {
    let id: String
    let actionType: String
    let description: String
    let success: Bool
    let errorMessage: String?  // Optional: only on failure
    let timestamp: String  // Always present
    let extraMetadata: ActionMetadataAPI?  // Optional: only for tool_execution
    // Using decoder.keyDecodingStrategy = .convertFromSnakeCase, so no CodingKeys needed
}

struct ActionMetadataAPI: Codable {
    let toolName: String?
    let params: [String: AnyCodableValue]?
    let result: String?
    let startTime: String?
    let endTime: String?
}

struct SSEEventAPI: Codable {
    let type: String
    let data: [String: AnyCodableValue]
    let timestamp: String
}

struct SearchResponse: Codable {
    let results: [SearchResult]
}

struct SearchResult: Codable {
    let id: String
    let title: String
    let preview: String
    let updatedAt: String
    let relevanceScore: Double
    // Using decoder.keyDecodingStrategy = .convertFromSnakeCase, so no CodingKeys needed
}

// MARK: - SSE Events

enum ConversationSSEEvent {
    case status(String)
    case state(String)  // "thinking", "editing", or "composing"
    case thinkingDelta(String)  // Real-time chain of thought streaming
    case content(String)
    case toolStart(String)  // Tool execution beginning
    case toolCall(ToolCallEvent)
    case toolComplete(ToolResultEvent)  // Tool execution complete
    case toolError(String)  // Tool execution failed
    case budgetUpdate(BudgetUpdateSSE)
    case complete  // All done
    case error(String)
}

struct BudgetUpdateSSE: Codable {
    let budget_remaining: Double
    let cost: Double
}

struct ToolCallEvent: Codable {
    let type: String
    let name: String  // Backend sends "name", not "tool"
    let params: [String: AnyCodableValue]  // Backend sends "params" with various types, not "arguments"
}

struct ToolResultEvent: Codable {
    let type: String
    let tool: String
    let result: String
    let success: Bool
}

// MARK: - Errors

enum ConversationError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case notFound
    case insufficientBudget
    case unauthorized
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .notFound:
            return "Conversation not found"
        case .insufficientBudget:
            return "Insufficient budget. Please upgrade to continue."
        case .unauthorized:
            return "Session expired. Please log in again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
