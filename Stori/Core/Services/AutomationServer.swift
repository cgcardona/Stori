//
//  AutomationServer.swift
//  Stori
//
//  Local HTTP server for external automation.
//  Enables agent swarms to drive Stori instances remotely.
//
//  DISABLED until Composer backend ships. Set isEnabled = true and add
//  com.apple.security.network.server entitlement to re-enable.
//

import Foundation
import Network
import Observation

// MARK: - Automation Request/Response

struct AutomationRequest: Codable {
    let prompt: String
    let mode: String?  // "generate" or "edit", defaults to contextual
}

struct AutomationResponse: Codable {
    let success: Bool
    let message: String
    let toolsExecuted: [String]
    let error: String?
}

// MARK: - Automation Server

@Observable
@MainActor
class AutomationServer {
    
    // MARK: - Configuration
    
    /// Set to true when Composer backend ships. When false, start() no-ops and the server never listens.
    static let isEnabled = false
    
    static let defaultPort: UInt16 = 10100
    
    // MARK: - Observable State
    
    var isRunning = false
    var port: UInt16 = AutomationServer.defaultPort
    var lastRequest: String?
    var requestCount: Int = 0
    
    // MARK: - Private
    
    @ObservationIgnored
    private var listener: NWListener?
    
    @ObservationIgnored
    private weak var composerClient: LLMComposerClient?
    
    @ObservationIgnored
    private weak var dispatcher: AICommandDispatcher?
    
    @ObservationIgnored
    private weak var projectManager: ProjectManager?
    
    // MARK: - Initialization
    
    init() {}
    
    func configure(
        composerClient: LLMComposerClient,
        dispatcher: AICommandDispatcher,
        projectManager: ProjectManager
    ) {
        self.composerClient = composerClient
        self.dispatcher = dispatcher
        self.projectManager = projectManager
    }
    
    // MARK: - Server Control
    
    func start(port: UInt16 = AutomationServer.defaultPort) {
        guard Self.isEnabled else {
            return
        }
        guard !isRunning else {
            return
        }
        
        self.port = port
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                    case .failed(let error):
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .global(qos: .userInitiated))
            
        } catch {
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }
    
    // MARK: - Connection Handling
    
    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    self?.handleRequest(data: data, connection: connection)
                }
            }
            
            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }
    
    private func handleRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, statusCode: 400, body: "Invalid request")
            return
        }
        
        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: "Invalid request")
            return
        }
        
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: "Invalid request line")
            return
        }
        
        let method = parts[0]
        let path = parts[1]
        
        // Extract body (after empty line)
        var body: String? = nil
        if let emptyLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines.dropFirst(emptyLineIndex + 1)
            body = bodyLines.joined(separator: "\r\n")
        }
        
        // Route request
        switch (method, path) {
        case ("GET", "/status"):
            handleStatus(connection: connection)
            
        case ("GET", "/health"):
            handleHealth(connection: connection)
            
        case ("POST", "/prompt"):
            handlePrompt(connection: connection, body: body)
            
        case ("OPTIONS", _):
            // CORS preflight
            sendResponse(connection: connection, statusCode: 200, body: "", corsHeaders: true)
            
        default:
            let usage = """
            Stori Automation Server
            
            Endpoints:
              GET  /status  - Server status
              GET  /health  - Health check
              POST /prompt  - Send a prompt to Stori
            
            Example:
              curl -X POST http://localhost:\(port)/prompt \\
                -H "Content-Type: application/json" \\
                -d '{"prompt": "Create a boom bap beat at 90 BPM"}'
            """
            sendResponse(connection: connection, statusCode: 200, body: usage)
        }
    }
    
    // MARK: - Endpoint Handlers
    
    private func handleStatus(connection: NWConnection) {
        Task { @MainActor in
            let status: [String: Any] = [
                "running": true,
                "port": Int(port),
                "requestCount": requestCount,
                "lastRequest": lastRequest ?? NSNull(),
                "composerConnected": composerClient?.isConnected ?? false,
                "projectLoaded": projectManager?.currentProject != nil,
                "projectName": projectManager?.currentProject?.name ?? NSNull()
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: status),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                sendResponse(connection: connection, statusCode: 200, body: jsonString, contentType: "application/json")
            }
        }
    }
    
    private func handleHealth(connection: NWConnection) {
        let health = ["status": "ok", "service": "stori-automation"]
        if let jsonData = try? JSONSerialization.data(withJSONObject: health),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendResponse(connection: connection, statusCode: 200, body: jsonString, contentType: "application/json")
        }
    }
    
    @ObservationIgnored
    private var requestTimestamps: [Date] = []
    private let maxRequestsPerMinute = 60

    private func checkRateLimit() -> Bool {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        requestTimestamps.removeAll { $0 < oneMinuteAgo }
        if requestTimestamps.count >= maxRequestsPerMinute { return false }
        requestTimestamps.append(now)
        return true
    }

    private func handlePrompt(connection: NWConnection, body: String?) {
        guard Self.isEnabled else { return }
        guard checkRateLimit() else {
            sendResponse(connection: connection, statusCode: 429, body: "Rate limit exceeded")
            return
        }
        guard let body = body, !body.isEmpty else {
            let error = AutomationResponse(
                success: false,
                message: "Missing request body",
                toolsExecuted: [],
                error: "Request body required with 'prompt' field"
            )
            sendJSONResponse(connection: connection, response: error, statusCode: 400)
            return
        }
        
        guard let jsonData = body.data(using: .utf8),
              let request = try? JSONDecoder().decode(AutomationRequest.self, from: jsonData) else {
            let error = AutomationResponse(
                success: false,
                message: "Invalid JSON",
                toolsExecuted: [],
                error: "Expected JSON with 'prompt' field"
            )
            sendJSONResponse(connection: connection, response: error, statusCode: 400)
            return
        }
        
        // Execute prompt asynchronously
        Task { @MainActor in
            await executePrompt(request: request, connection: connection)
        }
    }
    
    // MARK: - Prompt Execution
    
    private func executePrompt(request: AutomationRequest, connection: NWConnection) async {
        guard let composerClient = composerClient,
              let dispatcher = dispatcher else {
            let error = AutomationResponse(
                success: false,
                message: "Automation not configured",
                toolsExecuted: [],
                error: "ComposerClient or Dispatcher not available"
            )
            sendJSONResponse(connection: connection, response: error, statusCode: 500)
            return
        }
        
        guard composerClient.isConnected else {
            let error = AutomationResponse(
                success: false,
                message: "Not connected to backend",
                toolsExecuted: [],
                error: "Stori is not connected to the composer backend"
            )
            sendJSONResponse(connection: connection, response: error, statusCode: 503)
            return
        }
        
        requestCount += 1
        lastRequest = request.prompt
        
        
        // Determine mode based on context
        let mode = request.mode ?? (projectManager?.currentProject != nil ? "edit" : "generate")
        
        var toolsExecuted: [String] = []
        var errorMessage: String? = nil
        
        do {
            // Stream composition and execute tool calls
            for try await event in composerClient.composeStreaming(
                prompt: request.prompt,
                mode: mode,
                project: projectManager?.currentProject
            ) {
                switch event {
                case .toolComplete(let toolCall):
                    toolsExecuted.append(toolCall.tool)
                    
                    // Execute the tool call
                    let result = await dispatcher.executeToolCall(toolCall)
                    if !result.success {
                    }
                    
                case .error(let message):
                    errorMessage = message
                    
                case .complete:
                    break
                    
                default:
                    break
                }
            }
            
            let response = AutomationResponse(
                success: errorMessage == nil,
                message: errorMessage == nil 
                    ? "Executed \(toolsExecuted.count) tools"
                    : "Completed with errors",
                toolsExecuted: toolsExecuted,
                error: errorMessage
            )
            sendJSONResponse(connection: connection, response: response, statusCode: 200)
            
        } catch {
            let response = AutomationResponse(
                success: false,
                message: "Execution failed",
                toolsExecuted: toolsExecuted,
                error: error.localizedDescription
            )
            sendJSONResponse(connection: connection, response: response, statusCode: 500)
        }
    }
    
    // MARK: - Response Helpers
    
    private func sendJSONResponse(connection: NWConnection, response: AutomationResponse, statusCode: Int) {
        if let jsonData = try? JSONEncoder().encode(response),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendResponse(connection: connection, statusCode: statusCode, body: jsonString, contentType: "application/json")
        }
    }
    
    private func sendResponse(
        connection: NWConnection,
        statusCode: Int,
        body: String,
        contentType: String = "text/plain",
        corsHeaders: Bool = true
    ) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        case 503: statusText = "Service Unavailable"
        default: statusText = "Unknown"
        }
        
        var headers = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        """
        
        if corsHeaders {
            headers += """
            \r
            Access-Control-Allow-Origin: *\r
            Access-Control-Allow-Methods: GET, POST, OPTIONS\r
            Access-Control-Allow-Headers: Content-Type\r
            """
        }
        
        headers += "\r\n\r\n"
        
        let response = headers + body
        
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                }
                connection.cancel()
            })
        }
    }
}
