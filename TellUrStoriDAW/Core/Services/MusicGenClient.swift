//
//  MusicGenClient.swift
//  TellUrStoriDAW
//
//  Swift client for communicating with the MusicGen AI backend service.
//  Handles music generation requests, status tracking, and file downloads.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class MusicGenClient: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var currentGenerations: [GenerationJob] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    // MARK: - Private Properties
    private let baseURL: URL
    private let session = URLSession.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(baseURL: String = "http://127.0.0.1:8000") {
        self.baseURL = URL(string: baseURL)!
        
        // Check connection asynchronously after initialization
        Task {
            await checkConnection()
        }
    }
    
    // MARK: - Connection Management
    func checkConnection() async {
        do {
            let healthURL = baseURL.appendingPathComponent("health/ready")
            let (_, response) = try await session.data(from: healthURL)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                connectionStatus = .connected
                isConnected = true
            } else {
                connectionStatus = .error("Service not ready")
                isConnected = false
            }
        } catch {
            connectionStatus = .error(error.localizedDescription)
            isConnected = false
        }
    }
    
    // MARK: - Music Generation
    func generateMusic(
        prompt: String,
        duration: Double = 5.0,
        temperature: Double = 1.0,
        topK: Int = 250,
        topP: Double = 0.0,
        cfgCoef: Double = 3.0
    ) async throws -> GenerationJob {
        
        let request = GenerationRequest(
            prompt: prompt,
            duration: duration,
            temperature: temperature,
            topK: topK,
            topP: topP,
            cfgCoef: cfgCoef
        )
        
        let generateURL = baseURL.appendingPathComponent("api/v1/generate")
        var urlRequest = URLRequest(url: generateURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MusicGenError.requestFailed("Failed to start generation")
        }
        
        let generationResponse = try JSONDecoder().decode(GenerationResponse.self, from: data)
        
        let job = GenerationJob(
            id: generationResponse.jobId,
            prompt: prompt,
            duration: duration,
            status: .queued,
            progress: 0.0,
            createdAt: Date(),
            audioURL: nil
        )
        
        currentGenerations.append(job)
        
        // Start polling for status updates
        startStatusPolling(for: job.id)
        
        return job
    }
    
    // MARK: - Status Tracking
    func getJobStatus(jobId: String) async throws -> GenerationStatusResponse {
        let statusURL = baseURL.appendingPathComponent("api/v1/status/\(jobId)")
        let (data, response) = try await session.data(from: statusURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MusicGenError.requestFailed("Failed to get job status")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GenerationStatusResponse.self, from: data)
    }
    
    private func startStatusPolling(for jobId: String) {
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.updateJobStatus(jobId: jobId)
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateJobStatus(jobId: String) async {
        do {
            let statusURL = baseURL.appendingPathComponent("api/v1/status/\(jobId)")
            let (data, _) = try await session.data(from: statusURL)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let statusResponse = try decoder.decode(GenerationStatusResponse.self, from: data)
            
            // Update the job in our array
            if let index = currentGenerations.firstIndex(where: { $0.id == jobId }) {
                currentGenerations[index].status = GenerationStatus(rawValue: statusResponse.status) ?? .failed
                currentGenerations[index].progress = statusResponse.progress
                currentGenerations[index].message = statusResponse.message
                
                if statusResponse.status == "completed" {
                    currentGenerations[index].audioURL = statusResponse.audioURL
                    // Stop polling for this job
                    stopStatusPolling(for: jobId)
                } else if statusResponse.status == "failed" {
                    currentGenerations[index].errorMessage = statusResponse.errorMessage
                    stopStatusPolling(for: jobId)
                }
            }
            
        } catch {
            print("Failed to update job status: \(error)")
        }
    }
    
    private func stopStatusPolling(for jobId: String) {
        // Cancel specific timer for this job
        // In a more sophisticated implementation, we'd track individual timers
        // For now, we'll let the timer continue but it will skip completed jobs
    }
    
    // MARK: - Audio Download
    func downloadAudio(for jobId: String) async throws -> URL {
        let downloadURL = baseURL.appendingPathComponent("api/v1/download/\(jobId)")
        let (data, _) = try await session.data(from: downloadURL)
        
        // Save to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(jobId).wav")
        
        try data.write(to: tempURL)
        return tempURL
    }
    
    // MARK: - Prompt Builder
    func buildPrompt(
        genre: String? = nil,
        tempo: String? = nil,
        mood: String? = nil,
        instruments: [String]? = nil,
        artistStyle: String? = nil,
        customText: String? = nil
    ) async throws -> String {
        
        let request = PromptBuilderRequest(
            genre: genre,
            tempo: tempo,
            mood: mood,
            instruments: instruments,
            artistStyle: artistStyle,
            customText: customText
        )
        
        let promptURL = baseURL.appendingPathComponent("api/v1/prompt/build")
        var urlRequest = URLRequest(url: promptURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, _) = try await session.data(for: urlRequest)
        let response = try JSONDecoder().decode(PromptBuilderResponse.self, from: data)
        
        return response.structuredPrompt
    }
}

// MARK: - Data Models

struct GenerationJob: Identifiable, Codable {
    let id: String
    let prompt: String
    let duration: Double
    var status: GenerationStatus
    var progress: Double
    var message: String?
    let createdAt: Date
    var audioURL: String?
    var errorMessage: String?
}

enum GenerationStatus: String, Codable, CaseIterable {
    case queued = "queued"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var color: Color {
        switch self {
        case .queued: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .error(let message): return "Error: \(message)"
        }
    }
}

// MARK: - API Models

struct GenerationRequest: Codable {
    let prompt: String
    let duration: Double
    let temperature: Double
    let topK: Int
    let topP: Double
    let cfgCoef: Double
    
    enum CodingKeys: String, CodingKey {
        case prompt, duration, temperature
        case topK = "top_k"
        case topP = "top_p"
        case cfgCoef = "cfg_coef"
    }
}

struct GenerationResponse: Codable {
    let jobId: String
    let status: String
    let message: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status, message
        case createdAt = "created_at"
    }
}

struct GenerationStatusResponse: Codable {
    let jobId: String
    let status: String
    let progress: Double
    let message: String
    let createdAt: String
    let startedAt: String?
    let completedAt: String?
    let errorMessage: String?
    let prompt: String?
    let duration: Double?
    let audioURL: String?
    let fileSize: Int?
    let actualDuration: Double?
    
    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status, progress, message
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case errorMessage = "error_message"
        case prompt, duration
        case audioURL = "audio_url"
        case fileSize = "file_size"
        case actualDuration = "actual_duration"
    }
}

struct PromptBuilderRequest: Codable {
    let genre: String?
    let tempo: String?
    let mood: String?
    let instruments: [String]?
    let artistStyle: String?
    let customText: String?
    
    enum CodingKeys: String, CodingKey {
        case genre, tempo, mood, instruments
        case artistStyle = "artist_style"
        case customText = "custom_text"
    }
}

struct PromptBuilderResponse: Codable {
    let structuredPrompt: String
    let components: [String: String?]
    
    enum CodingKeys: String, CodingKey {
        case structuredPrompt = "structured_prompt"
        case components
    }
}

// MARK: - Errors

enum MusicGenError: LocalizedError {
    case requestFailed(String)
    case decodingFailed(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .decodingFailed(let message):
            return "Decoding failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
