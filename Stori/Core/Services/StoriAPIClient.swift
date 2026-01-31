//
//  StoriAPIClient.swift
//  Stori
//
//  Authenticated API client for Stori Composer backend
//

import Foundation

// NOTE: Composer features are disabled for initial open source release
// This client remains in the codebase but is not currently used

// MARK: - SSE Event Model

struct SSEEvent: Codable {
    let type: String
    let message: String?
    let content: String?
    let tool: String?
    let params: [String: AnyCodableValue]?
    let success: Bool?
    
    enum EventType: String {
        case status
        case thinking
        case toolStart = "tool_start"
        case toolCall = "tool_call"
        case toolComplete = "tool_complete"
        case toolError = "tool_error"
        case complete
        case error
    }
    
    var eventType: EventType? {
        EventType(rawValue: type)
    }
}

// MARK: - API Client

@Observable
class StoriAPIClient {
    static let shared = StoriAPIClient()
    
    /// Base URL for API requests - configured via AppConfig
    let baseURL = AppConfig.apiBaseURL
    
    private init() {
        // Validate secure connection on initialization
        AppConfig.validateSecureConnection()
    }
    
    // MARK: - Private Helpers
    
    /// Get authorization header with token from Keychain
    private func authHeader() throws -> String {
        guard let token = try? TokenManager.shared.getToken() else {
            throw AuthError.noToken
        }
        return "Bearer \(token)"
    }
    
    // MARK: - Public API
    
    /// Stream composition with SSE
    func streamCompose(
        prompt: String,
        mode: String = "create",
        project: [String: Any]? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get token
                    let authHeader = try self.authHeader()
                    
                    guard let url = URL(string: "\(self.baseURL)/api/v1/compose/stream") else {
                        continuation.finish(throwing: AuthError.invalidURL)
                        return
                    }
                    
                    // Build request body
                    var requestBody: [String: Any] = [
                        "prompt": prompt,
                        "mode": mode
                    ]
                    if let project = project {
                        requestBody["project"] = project
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(authHeader, forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                    request.timeoutInterval = AppConfig.extendedTimeout
                    
                    // Stream SSE events
                    #if DEBUG
                    #endif
                    
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    #if DEBUG
                    #endif
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        #if DEBUG
                        #endif
                        continuation.finish(throwing: AuthError.invalidResponse)
                        return
                    }
                    
                    #if DEBUG
                    // SECURITY: Only log non-sensitive headers
                    let safeHeaderKeys = ["Content-Type", "Content-Length", "Date", "Server"]
                    let safeHeaders = httpResponse.allHeaderFields.filter { key, _ in
                        safeHeaderKeys.contains(key as? String ?? "")
                    }
                    #endif
                    
                    // Handle 401 Unauthorized
                    if httpResponse.statusCode == 401 {
                        // Clear invalid token
                        try? TokenManager.shared.deleteToken()
                        
                        // Post notification for UI to show token input
                        await MainActor.run {
                            NotificationCenter.default.post(name: .tokenExpired, object: nil)
                        }
                        
                        continuation.finish(throwing: AuthError.tokenExpired)
                        return
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: AuthError.serverError(httpResponse.statusCode))
                        return
                    }
                    
                    // Parse SSE stream
                    var buffer = ""
                    for try await byte in bytes {
                        buffer.append(Character(UnicodeScalar(byte)))
                        
                        if buffer.hasSuffix("\n\n") {
                            let lines = buffer.split(separator: "\n")
                            for line in lines {
                                if line.hasPrefix("data: ") {
                                    let jsonString = String(line.dropFirst(6))
                                    
                                    // Log raw response for debugging
                                    #if DEBUG
                                    #endif
                                    
                                    if let data = jsonString.data(using: .utf8) {
                                        do {
                                            let event = try JSONDecoder().decode(SSEEvent.self, from: data)
                                            continuation.yield(event)
                                        } catch {
                                            #if DEBUG
                                            #endif
                                            // Continue processing other events even if one fails
                                        }
                                    }
                                }
                            }
                            buffer = ""
                        }
                    }
                    
                    continuation.finish()
                } catch let error as AuthError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AuthError.networkError(error))
                }
            }
        }
    }
    
    /// Check if backend is reachable
    func checkConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/health") else {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
}
