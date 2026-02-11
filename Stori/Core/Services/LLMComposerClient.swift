//
//  LLMComposerClient.swift
//  Stori
//
//  Client for the AI Composer service that generates and modifies projects
//  through natural language prompts.
//

import Foundation
import Observation

// MARK: - Composer Models

struct ComposerToolCall: Codable, Identifiable, Sendable {
    var id: String { "\(tool)-\(UUID().uuidString)" }
    let tool: String
    let params: [String: AnyCodableValue]
}

struct ComposerRequest: Codable {
    let mode: String  // "generate" or "edit"
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

struct ProjectContext: Codable {
    let projectId: String
    let name: String
    let tempo: Double
    let keySignature: String
    let timeSignature: String
    let sampleRate: Double
    let durationBeats: Double
    let trackCount: Int
    let busCount: Int
    let tracks: [TrackSummary]
}

struct TrackSummary: Codable {
    let trackId: String
    let name: String
    let type: String
    let color: String
    
    // Mixer Settings
    let volume: Double
    let pan: Double
    let isMuted: Bool
    let isSoloed: Bool
    
    // Instrument/MIDI
    let instrument: String?
    let gmProgram: Int?
    let drumKitId: String?
    
    // Regions
    let audioRegionCount: Int
    let midiRegionCount: Int
    let regions: [RegionSummary]
    
    // Effects & Processing
    let insertEffects: [EffectSummary]
    let sends: [SendSummary]
    
    // Automation
    let automationLanes: [AutomationSummary]
    let hasAutomation: Bool
    
    // Routing
    let inputSource: String
    let outputDestination: String
    
    // State
    let isEnabled: Bool
    let isFrozen: Bool
}

struct RegionSummary: Codable {
    let regionId: String
    let name: String
    let type: String  // "audio" or "midi"
    let startBeat: Double
    let durationBeats: Double
    let noteCount: Int?  // Only for MIDI regions
    let isAIGenerated: Bool
    let isMuted: Bool
}

struct EffectSummary: Codable {
    let effectId: String
    let name: String
    let type: String
    let isEnabled: Bool
}

struct SendSummary: Codable {
    let busId: String
    let busName: String?
    let level: Double
    let isEnabled: Bool
}

struct AutomationSummary: Codable {
    let parameter: String
    let pointCount: Int
    let isVisible: Bool
}

struct ComposerResponse: Codable, Sendable {
    let success: Bool
    let toolCalls: [ComposerToolCall]
    let rawResponse: String?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case toolCalls = "tool_calls"
        case rawResponse = "raw_response"
        case error
    }
}

// MARK: - Streaming Models

enum ComposerStreamEvent: Sendable {
    case status(String)
    case content(String)
    case toolStart(String)
    case toolComplete(ComposerToolCall)
    case toolError(String, String)  // (tool name, error message) - backend resolution failed
    case budgetUpdate(Double, Double)  // (remaining, cost)
    case complete(ComposerResponse)
    case error(String)
}

struct StreamEventData: Codable {
    let type: String
    let message: String?
    let chunk: String?
    let tool: String?
    let params: [String: AnyCodableValue]?
    let success: Bool?
    let toolCalls: [[String: AnyCodableValue]]?
    let error: String?  // For tool_error events
    
    enum CodingKeys: String, CodingKey {
        case type, message, chunk, tool, params, success, error
        case toolCalls = "tool_calls"
    }
}

enum ComposerError: Error, LocalizedError {
    case notConnected
    case requestFailed(String)
    case invalidResponse
    case networkError(Error)
    case budgetExhausted(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to AI Composer service"
        case .requestFailed(let message):
            return "Composer request failed: \(message)"
        case .invalidResponse:
            return "Invalid response from composer service"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .budgetExhausted(let message):
            return message
        }
    }
    
    /// Check if this error is a budget exhaustion error
    var isBudgetExhausted: Bool {
        if case .budgetExhausted = self { return true }
        return false
    }
}

// MARK: - AnyCodableValue for handling dynamic JSON

enum AnyCodableValue: Codable, Sendable {
    static let maxNestingDepth = 20

    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        if decoder.codingPath.count >= Self.maxNestingDepth {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "JSON nesting depth exceeds maximum (\(Self.maxNestingDepth))"
            ))
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.typeMismatch(AnyCodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    
    var intValue: Int? {
        if case .int(let value) = self { return value }
        if case .double(let value) = self { return Int(value) }
        return nil
    }
    
    var doubleValue: Double? {
        if case .double(let value) = self { return value }
        if case .int(let value) = self { return Double(value) }
        return nil
    }
    
    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
    
    var arrayValue: [AnyCodableValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
    
    var dictionaryValue: [String: AnyCodableValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }
}

// MARK: - LLM Composer Client

@Observable
@MainActor
class LLMComposerClient {
    
    // MARK: - Observable Properties
    var isConnected = false
    var isProcessing = false
    var lastError: String?
    var lastResponse: ComposerResponse?
    
    // MARK: - Private Properties
    @ObservationIgnored
    private let baseURL: URL
    @ObservationIgnored
    private let session: URLSession
    
    // MARK: - Task Lifecycle Management
    
    @ObservationIgnored
    private var streamingTask: Task<Void, Never>?
    @ObservationIgnored
    private var cleanupTask: Task<Void, Never>?

    /// M-7: Redact paths, IPs, and long tokens from error messages shown to UI.
    private static func sanitizeErrorMessage(_ error: String) -> String {
        var s = error
        s = s.replacingOccurrences(of: #"/[A-Za-z0-9_/\-.]+\.(swift|py|js)"#, with: "[PATH]", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#, with: "[IP]", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b[A-Za-z0-9+/]{32,}\b"#, with: "[REDACTED]", options: .regularExpression)
        return s
    }

    // MARK: - Initialization
    
    /// Initialize with the composer service URL
    /// - Parameter baseURL: The composer service URL (default: AppConfig.apiBaseURL from env/Config.plist/Info.plist)
    /// - Note: Uses fatalError in DEBUG for invalid URLs, falls back to AppConfig in production
    init(baseURL: String = AppConfig.apiBaseURL) {
        let resolved = baseURL.isEmpty ? AppConfig.apiBaseURL : baseURL
        if let url = URL(string: resolved),
           let scheme = url.scheme,
           ["http", "https"].contains(scheme),
           url.host != nil {
            self.baseURL = url
        } else {
            #if DEBUG
            fatalError("Invalid baseURL provided to LLMComposerClient: \(resolved)")
            #else
            self.baseURL = URL(string: "https://stage.example.com")!
            #endif
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120  // 2 minutes for LLM generation
        config.timeoutIntervalForResource = 300  // 5 minutes total
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "Connection": "keep-alive",
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
        // Note: Don't auto-check here - let the view control when to check
        // to avoid duplicate checks during SwiftUI view lifecycle
    }
    
    // MARK: - Connection
    
    @ObservationIgnored
    private var isCheckingConnection = false
    
    func checkConnection() async {
        // Skip if already connected or check in progress
        guard !isConnected && !isCheckingConnection else { return }
        isCheckingConnection = true
        defer { isCheckingConnection = false }
        
        do {
            let healthURL = baseURL.appendingPathComponent("api/v1/health")
            let (data, response) = try await session.data(from: healthURL)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                // Parse health response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String,
                   status == "ok" {
                    isConnected = true
                    return
                }
            }
            isConnected = false
        } catch {
            isConnected = false
            lastError = error.localizedDescription
        }
    }
    
    // MARK: - Compose
    
    /// Generate or edit a project based on natural language prompt
    /// - Parameters:
    ///   - prompt: Natural language description of what to create/modify
    ///   - mode: "generate" for new song, "edit" for modifications
    ///   - project: Current project (for edit mode)
    /// - Returns: ComposerResponse with tool calls to execute
    func compose(prompt: String, mode: String = "generate", project: AudioProject? = nil) async throws -> ComposerResponse {
        guard isConnected else {
            throw ComposerError.notConnected
        }
        
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        // Build exhaustive context from current project if editing
        let context = project.map { buildProjectContext(from: $0) }
        
        let request = ComposerRequest(mode: mode, prompt: prompt, project: context)
        
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/v1/compose"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        do {
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ComposerError.invalidResponse
            }
            
            
            if httpResponse.statusCode != 200 {
                let raw = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ComposerError.requestFailed("HTTP \(httpResponse.statusCode): \(Self.sanitizeErrorMessage(raw))")
            }
            
            let decoder = JSONDecoder()
            let composerResponse = try decoder.decode(ComposerResponse.self, from: data)
            
            lastResponse = composerResponse
            return composerResponse
            
        } catch let error as ComposerError {
            lastError = Self.sanitizeErrorMessage(error.localizedDescription)
            throw error
        } catch let urlError as URLError {
            lastError = Self.sanitizeErrorMessage(urlError.localizedDescription)
            throw ComposerError.networkError(urlError)
        } catch {
            lastError = Self.sanitizeErrorMessage(error.localizedDescription)
            throw ComposerError.networkError(error)
        }
    }
    
    /// Quick method for generating a new song
    func generateSong(prompt: String) async throws -> ComposerResponse {
        return try await compose(prompt: prompt, mode: "generate", project: nil)
    }
    
    /// Quick method for editing an existing project
    func editProject(prompt: String, project: AudioProject) async throws -> ComposerResponse {
        return try await compose(prompt: prompt, mode: "edit", project: project)
    }
    
    // MARK: - Streaming API
    
    /// Current streaming status message
    var streamingStatus: String = ""
    
    /// Accumulated content from streaming
    var streamingContent: String = ""
    
    /// Tools discovered during streaming
    var streamingTools: [String] = []
    
    /// Stream composition with real-time updates
    /// - Parameters:
    ///   - prompt: Natural language description of what to create/modify
    ///   - mode: "generate" for new song, "edit" for modifications
    ///   - project: Current project (for edit mode context)
    ///   - model: Optional model ID to use (defaults to user's selected model)
    ///   - storePrompt: Whether to store the prompt for service improvement (defaults to user setting)
    func composeStreaming(
        prompt: String,
        mode: String = "generate",
        project: AudioProject? = nil,
        model: String? = nil,
        storePrompt: Bool? = nil
    ) -> AsyncThrowingStream<ComposerStreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            // Cancel any existing streaming task before starting new one
            streamingTask?.cancel()
            streamingTask = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                guard await MainActor.run(body: { self.isConnected }) else {
                    continuation.finish(throwing: ComposerError.notConnected)
                    return
                }
                
                await MainActor.run {
                    self.isProcessing = true
                    self.streamingStatus = "Starting..."
                    self.streamingContent = ""
                    self.streamingTools = []
                }
                
                defer {
                    // Cancel previous cleanup task if any
                    self.cleanupTask?.cancel()
                    self.cleanupTask = Task { @MainActor [weak self] in
                        self?.isProcessing = false
                        self?.cleanupTask = nil
                    }
                    // Clear streaming task reference
                    self.streamingTask = nil
                }
                
                // Build exhaustive context
                let context = project.map { buildProjectContext(from: $0) }
                
                // 🔍 DEBUG: Log project context being sent
                if let ctx = context {
                    for track in ctx.tracks {
                    }
                } else {
                }
                
                // Get model and privacy settings from UserManager if not specified
                let selectedModel = await MainActor.run { model ?? UserManager.shared.selectedModelId }
                let shouldStorePrompt = await MainActor.run { storePrompt ?? UserManager.shared.storePrompts }
                
                // Only include model in request if not empty (backend will use default)
                let modelToSend = selectedModel.isEmpty ? nil : selectedModel
                
                let request = ComposerRequest(
                    mode: mode,
                    prompt: prompt,
                    project: context,
                    model: modelToSend,
                    storePrompt: shouldStorePrompt
                )
                
                var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/v1/compose/stream"))
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                
                // Add JWT authorization
                guard let token = try? TokenManager.shared.getToken() else {
                    continuation.finish(throwing: AuthError.noToken)
                    return
                }
                urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let encoder = JSONEncoder()
                do {
                    urlRequest.httpBody = try encoder.encode(request)
                    
                    // 🔍 DEBUG: Log the actual JSON being sent
                    if let httpBody = urlRequest.httpBody,
                       let jsonString = String(data: httpBody, encoding: .utf8) {
                        let preview = jsonString.prefix(500)  // First 500 chars
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                
                do {
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ComposerError.invalidResponse)
                        return
                    }
                    
                    // SECURITY: Only log non-sensitive headers
                    let safeHeaderKeys = ["Content-Type", "Content-Length", "Date", "Server"]
                    let safeHeaders = httpResponse.allHeaderFields.filter { key, _ in
                        safeHeaderKeys.contains(key as? String ?? "")
                    }
                    
                    // Handle 401 Unauthorized (token expired)
                    if httpResponse.statusCode == 401 {
                        // Clear invalid token
                        try? TokenManager.shared.deleteToken()
                        // Post notification for UI
                        await MainActor.run {
                            NotificationCenter.default.post(name: .tokenExpired, object: nil)
                        }
                        continuation.finish(throwing: AuthError.tokenExpired)
                        return
                    }
                    
                    // Handle 402 Payment Required (budget exhausted)
                    if httpResponse.statusCode == 402 {
                        
                        // Try to parse the error response for details
                        var errorMessage = "Your budget is exhausted. Please contact support for more credits."
                        var remainingBudget: Double = 0
                        
                        // Read the response body for details
                        var responseData = Data()
                        for try await byte in bytes {
                            responseData.append(byte)
                        }
                        
                        if let errorResponse = try? JSONDecoder().decode(BudgetExhaustedError.self, from: responseData) {
                            errorMessage = errorResponse.detail.message
                            remainingBudget = errorResponse.detail.budgetRemaining
                            
                            // Update UserManager budget
                            await MainActor.run {
                                UserManager.shared.budget.remaining = remainingBudget
                            }
                        }
                        
                        // Post notification for UI
                        await MainActor.run {
                            NotificationCenter.default.post(name: .budgetExhausted, object: nil)
                        }
                        
                        continuation.finish(throwing: ComposerError.budgetExhausted(errorMessage))
                        return
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: ComposerError.requestFailed("HTTP \(httpResponse.statusCode)"))
                        return
                    }
                    
                    // Check for X-Budget-Remaining header
                    if let budgetHeader = httpResponse.value(forHTTPHeaderField: "X-Budget-Remaining"),
                       let remaining = Double(budgetHeader) {
                        await MainActor.run {
                            UserManager.shared.updateBudget(remaining: remaining)
                        }
                    }
                    
                    var eventCount = 0
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6))
                            eventCount += 1
                            
                            // 🔍 DEBUG: Log ALL SSE events
                            let truncated = jsonStr.count > 200 ? String(jsonStr.prefix(200)) + "..." : jsonStr
                            
                            guard let data = jsonStr.data(using: .utf8) else { continue }
                            
                            do {
                                let event = try JSONDecoder().decode(StreamEventData.self, from: data)
                                // M-6: Reject malformed event type (alphanumeric + underscore only)
                                guard event.type.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), event.type.count <= 32 else {
                                    continue
                                }
                                switch event.type {
                                case "status":
                                    if let message = event.message {
                                        await MainActor.run { streamingStatus = message }
                                        continuation.yield(.status(message))
                                    }
                                    
                                case "content":
                                    if let chunk = event.chunk {
                                        await MainActor.run { streamingContent += chunk }
                                        continuation.yield(.content(chunk))
                                    }
                                    
                                case "tool_start":
                                    if let tool = event.tool {
                                        await MainActor.run { streamingTools.append(tool) }
                                        continuation.yield(.toolStart(tool))
                                    }
                                    
                                case "tool_call":
                                    // Real-time tool execution (Tier 2 DAW tools)
                                    if let tool = event.tool, let params = event.params {
                                        
                                        // 🔍 DEBUG: Log trackId specifically
                                        if let trackId = params["trackId"] {
                                            if case .string(let str) = trackId {
                                            }
                                        }
                                        
                                        let toolCall = ComposerToolCall(tool: tool, params: params)
                                        continuation.yield(.toolComplete(toolCall))
                                    } else {
                                    }
                                    
                                case "tool_complete":
                                    // Tool finished on backend (Tier 1 music gen tools)
                                    break
                                
                                case "tool_error":
                                    // Backend failed to resolve tool parameters
                                    if let tool = event.tool, let errorMsg = event.error ?? event.message {
                                        continuation.yield(.toolError(tool, errorMsg))
                                    } else {
                                    }
                                
                                case "budget_update":
                                    // Real-time budget update from streaming response
                                    if let budgetData = jsonStr.data(using: .utf8),
                                       let budgetEvent = try? JSONDecoder().decode(BudgetUpdateEvent.self, from: budgetData) {
                                        
                                        // Update UserManager
                                        await MainActor.run {
                                            UserManager.shared.updateBudget(from: budgetEvent)
                                        }
                                        
                                        continuation.yield(.budgetUpdate(budgetEvent.budgetRemaining, budgetEvent.cost))
                                    }
                                    
                                case "complete":
                                    if let toolCallsData = event.toolCalls {
                                        var toolCalls: [ComposerToolCall] = []
                                        for tcData in toolCallsData {
                                            if let tool = tcData["tool"]?.stringValue,
                                               let paramsValue = tcData["params"],
                                               case .dictionary(let params) = paramsValue {
                                                toolCalls.append(ComposerToolCall(tool: tool, params: params))
                                            }
                                        }
                                        let response = ComposerResponse(
                                            success: event.success ?? true,
                                            toolCalls: toolCalls,
                                            rawResponse: nil,
                                            error: nil
                                        )
                                        await MainActor.run { lastResponse = response }
                                        continuation.yield(.complete(response))
                                    }
                                    
                                case "error":
                                    if let message = event.message {
                                        let safe = Self.sanitizeErrorMessage(message)
                                        await MainActor.run { lastError = safe }
                                        continuation.yield(.error(safe))
                                    }
                                    
                                default:
                                    break
                                }
                            } catch {
                                // Skip unparseable events
                            }
                        }
                    }
                    
                    continuation.finish()
                    
                } catch {
                    await MainActor.run { lastError = Self.sanitizeErrorMessage(error.localizedDescription) }
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Helper Methods for Building Context
    
    /// Build exhaustive project context for LLM
    private func buildProjectContext(from project: AudioProject) -> ProjectContext {
        ProjectContext(
            projectId: project.id.uuidString,
            name: project.name,
            tempo: project.tempo,
            keySignature: project.keySignature,
            timeSignature: project.timeSignature.description,
            sampleRate: project.sampleRate,
            durationBeats: project.durationBeats,
            trackCount: project.tracks.count,
            busCount: project.buses.count,
            tracks: project.tracks.map { buildTrackSummary(from: $0, buses: project.buses) }
        )
    }
    
    /// Build track summary with all details
    private func buildTrackSummary(from track: AudioTrack, buses: [MixerBus]) -> TrackSummary {
        let regions = buildRegionSummaries(from: track)
        let effects = buildEffectSummaries(from: track)
        let sends = buildSendSummaries(from: track, buses: buses)
        let automation = buildAutomationSummaries(from: track)
        
        return TrackSummary(
            trackId: track.id.uuidString,
            name: track.name,
            type: track.trackTypeLabel,
            color: String(describing: track.color),
            volume: Double(track.mixerSettings.volume),
            pan: Double(track.mixerSettings.pan),
            isMuted: track.mixerSettings.isMuted,
            isSoloed: track.mixerSettings.isSolo,
            instrument: track.voicePreset,
            gmProgram: track.gmProgram,
            drumKitId: track.drumKitId,
            audioRegionCount: track.regions.count,
            midiRegionCount: track.midiRegions.count,
            regions: regions,
            insertEffects: effects,
            sends: sends,
            automationLanes: automation,
            hasAutomation: track.hasAutomationData,
            inputSource: track.inputSource.displayName,
            outputDestination: track.outputDestination.displayName,
            isEnabled: track.isEnabled,
            isFrozen: track.isFrozen
        )
    }
    
    /// Build region summaries (audio + MIDI)
    private func buildRegionSummaries(from track: AudioTrack) -> [RegionSummary] {
        let audioRegions = track.regions.map { region in
            RegionSummary(
                regionId: region.id.uuidString,
                name: region.audioFile.name,
                type: "audio",
                startBeat: region.startBeat,
                durationBeats: region.durationBeats,
                noteCount: nil,
                isAIGenerated: region.aiGenerationMetadata != nil,
                isMuted: false  // AudioRegion doesn't have isMuted
            )
        }
        
        let midiRegions = track.midiRegions.map { region in
            RegionSummary(
                regionId: region.id.uuidString,
                name: region.name,
                type: "midi",
                startBeat: region.startBeat,
                durationBeats: region.durationBeats,
                noteCount: region.notes.count,
                isAIGenerated: false,
                isMuted: region.isMuted
            )
        }
        
        return audioRegions + midiRegions
    }
    
    /// Build effect summaries
    private func buildEffectSummaries(from track: AudioTrack) -> [EffectSummary] {
        track.pluginConfigs.map { plugin in
            EffectSummary(
                effectId: plugin.id.uuidString,
                name: plugin.pluginName,
                type: plugin.pluginName.lowercased(),  // Use plugin name as type
                isEnabled: !plugin.isBypassed
            )
        }
    }
    
    /// Build send summaries
    private func buildSendSummaries(from track: AudioTrack, buses: [MixerBus]) -> [SendSummary] {
        track.sends.compactMap { send in
            let bus = buses.first { $0.id == send.busId }
            return SendSummary(
                busId: send.busId.uuidString,
                busName: bus?.name,
                level: send.sendLevel,
                isEnabled: !send.isMuted
            )
        }
    }
    
    /// Build automation summaries
    private func buildAutomationSummaries(from track: AudioTrack) -> [AutomationSummary] {
        track.automationLanes.filter { !$0.points.isEmpty }.map { lane in
            AutomationSummary(
                parameter: lane.parameter.rawValue,
                pointCount: lane.points.count,
                isVisible: lane.isVisible
            )
        }
    }
    
    // No deinit needed — all tasks use [weak self] and terminate naturally when this object is released.
}
