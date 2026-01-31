//
//  AICommandDispatcher.swift
//  Stori
//
//  Executes AI-generated tool calls against the ProjectManager.
//  Bridges the LLM composer output to actual project mutations.
//

import Foundation
import SwiftUI
import Observation

// MARK: - Tool Execution Result

struct ToolExecutionResult {
    let tool: String
    let success: Bool
    let data: [String: String]  // e.g., ["trackId": "uuid-string"]
    let error: String?
}

struct BatchExecutionResult {
    let results: [ToolExecutionResult]
    let success: Bool
    let totalToolCalls: Int
    let successfulCalls: Int
    let message: String
}

// MARK: - AI Command Dispatcher

@Observable
@MainActor
class AICommandDispatcher {
    
    // MARK: - Dependencies
    @ObservationIgnored
    private weak var projectManager: ProjectManager?
    @ObservationIgnored
    private weak var audioEngine: AudioEngine?
    @ObservationIgnored
    private weak var undoService: UndoService?
    
    // MARK: - Observable State
    var isExecuting = false
    var lastResult: BatchExecutionResult?
    var executionProgress: Double = 0
    
    // MARK: - Initialization
    
    init(projectManager: ProjectManager, audioEngine: AudioEngine? = nil, undoService: UndoService? = nil) {
        self.projectManager = projectManager
        self.audioEngine = audioEngine
        self.undoService = undoService
    }
    
    // MARK: - Batch Execution
    
    /// Execute a batch of tool calls from the composer response
    ///
    /// Backend sends fully-resolved params with UUIDs - no variable resolution needed.
    /// - Parameter toolCalls: Array of tool calls from ComposerResponse
    /// - Returns: BatchExecutionResult with details of each tool call
    func executeBatch(_ toolCalls: [ComposerToolCall]) async -> BatchExecutionResult {
        
        guard let projectManager = projectManager else {
            return BatchExecutionResult(
                results: [],
                success: false,
                totalToolCalls: toolCalls.count,
                successfulCalls: 0,
                message: "ProjectManager not available"
            )
        }
        
        isExecuting = true
        executionProgress = 0
        defer { 
            isExecuting = false 
            executionProgress = 1.0
        }
        
        // Begin undo group
        undoService?.beginGroup(named: "AI Composition")
        defer { undoService?.endGroup() }
        
        var results: [ToolExecutionResult] = []
        
        for (index, toolCall) in toolCalls.enumerated() {
            executionProgress = Double(index) / Double(toolCalls.count)
            
            
            // Defense-in-depth: validate params are properly resolved
            if let validationError = validateToolParams(toolCall.tool, toolCall.params) {
                results.append(ToolExecutionResult(
                    tool: toolCall.tool,
                    success: false,
                    data: [:],
                    error: validationError
                ))
                continue
            }
            
            // Execute the tool call with already-resolved params from backend
            let result = await executeToolCallInternal(
                tool: toolCall.tool,
                params: toolCall.params,
                projectManager: projectManager
            )
            
            
            results.append(result)
            
            // If createProject failed, warn that subsequent tools will likely fail
            if !result.success && (toolCall.tool.contains("create") && toolCall.tool.contains("project")) {
            }
        }
        
        let successCount = results.filter { $0.success }.count
        
        let batchResult = BatchExecutionResult(
            results: results,
            success: successCount == results.count,
            totalToolCalls: toolCalls.count,
            successfulCalls: successCount,
            message: successCount == results.count 
                ? "Successfully executed \(successCount) changes"
                : "Executed \(successCount)/\(results.count) changes"
        )
        
        lastResult = batchResult
        
        // Sync audio engine with the updated project
        if let project = projectManager.currentProject {
            audioEngine?.loadProject(project)
        }
        
        // Post notification for UI update
        NotificationCenter.default.post(name: .projectUpdated, object: projectManager.currentProject)
        
        return batchResult
    }
    
    /// Execute a single tool call (for streaming execution)
    ///
    /// Backend sends fully-resolved params with UUIDs - no variable resolution needed.
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: ToolExecutionResult with details
    func executeToolCall(_ toolCall: ComposerToolCall) async -> ToolExecutionResult {
        guard let projectManager = projectManager else {
            return ToolExecutionResult(
                tool: toolCall.tool,
                success: false,
                data: [:],
                error: "ProjectManager not available"
            )
        }
        
        // Defense-in-depth: validate params are properly resolved
        if let validationError = validateToolParams(toolCall.tool, toolCall.params) {
            return ToolExecutionResult(
                tool: toolCall.tool,
                success: false,
                data: [:],
                error: validationError
            )
        }
        
        
        let result = await executeToolCallInternal(
            tool: toolCall.tool,
            params: toolCall.params,
            projectManager: projectManager
        )
        
        // Sync audio engine after each tool call
        if result.success, let project = projectManager.currentProject {
            audioEngine?.loadProject(project)
        }
        
        return result
    }
    
    // MARK: - Tool Execution
    
    /// Extract Double from AnyCodableValue (backend may send numbers or strings like "16")
    private func doubleFromParam(_ value: AnyCodableValue?) -> Double? {
        guard let value = value else { return nil }
        if let d = value.doubleValue { return d }
        if let i = value.intValue { return Double(i) }
        if let s = value.stringValue, let parsed = Double(s) { return parsed }
        return nil
    }
    
    private func executeToolCallInternal(
        tool: String,
        params: [String: AnyCodableValue],
        projectManager: ProjectManager
    ) async -> ToolExecutionResult {
        
        // Normalize MCP-style tool names (stori_add_midi_track -> addMidiTrack)
        let normalizedTool = normalizeMCPToolName(tool)
        
        do {
            switch normalizedTool {
                
            // MARK: Project-Level Tools
            case "createProject":
                let requestedName = params["name"]?.stringValue ?? "Untitled"
                let tempo = params["tempo"]?.doubleValue ?? 120.0
                let keySignature = params["keySignature"]?.stringValue ?? "C"
                
                // Auto-increment name if project already exists
                var finalName = requestedName
                var attempt = 1
                while projectManager.projectExists(withName: finalName) {
                    attempt += 1
                    finalName = "\(requestedName) \(attempt)"
                }
                
                if finalName != requestedName {
                }
                
                try projectManager.createNewProject(name: finalName, tempo: tempo)
                
                if var project = projectManager.currentProject {
                    project.keySignature = keySignature
                    // Remove the default empty track that createNewProject adds
                    if project.tracks.count == 1 && project.tracks[0].name == "Track 1" {
                        project.tracks.removeAll()
                    }
                    projectManager.currentProject = project
                }
                
                return ToolExecutionResult(
                    tool: tool,
                    success: true,
                    data: ["projectId": projectManager.currentProject?.id.uuidString ?? ""],
                    error: nil
                )
                
            case "setTempo":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                let bpm = params["tempo"]?.doubleValue ?? 120.0
                project.tempo = max(20, min(300, bpm))
                projectManager.currentProject = project
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "setKeySignature":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                let key = params["key"]?.stringValue ?? "C"
                project.keySignature = key
                projectManager.currentProject = project
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "readProject":
                guard let project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                
                // Return comprehensive project info as JSON string
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                
                guard let jsonData = try? encoder.encode(project),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    throw AICommandError.invalidParameter("Failed to serialize project")
                }
                
                return ToolExecutionResult(
                    tool: tool, 
                    success: true, 
                    data: ["projectJson": jsonString],
                    error: nil
                )
                
            // MARK: Track Tools
            case "addMidiTrack":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                
                let name = params["name"]?.stringValue ?? "MIDI Track"
                let colorName = params["color"]?.stringValue ?? "blue"
                let color = parseTrackColor(colorName)
                
                // Entity ID contract (SWIFT_INTEGRATION.md): backend sends trackId; we must use it so later tools (add_region, etc.) find this track.
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId (required; backend must send track UUID for addMidiTrack)")
                }
                
                var track = AudioTrack(id: trackId, name: name, trackType: .midi, color: color)
                
                // Set instrument type
                if let gmProgram = params["gmProgram"]?.intValue {
                    track.gmProgram = gmProgram
                    track.voicePreset = gmProgramName(gmProgram)
                }
                if let drumKitId = params["drumKitId"]?.stringValue, !drumKitId.isEmpty {
                    track.drumKitId = drumKitId
                    track.voicePreset = drumKitId
                }
                if let synthPresetId = params["synthPresetId"]?.intValue {
                    track.synthPresetId = synthPresetId
                }
                
                project.addTrack(track)
                projectManager.currentProject = project
                
                
                return ToolExecutionResult(
                    tool: tool,
                    success: true,
                    data: ["trackId": track.id.uuidString],
                    error: nil
                )
                
            case "setTrackVolume":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                let volume = params["volume"]?.doubleValue ?? 0.8
                let clampedVolume = Float(max(0, min(1, volume)))
                
                // Update project model (for UI)
                if let index = project.tracks.firstIndex(where: { $0.id == trackId }) {
                    project.tracks[index].mixerSettings.volume = clampedVolume
                    projectManager.currentProject = project
                }
                
                // Update audio engine (for real-time audio)
                audioEngine?.updateTrackVolume(trackId: trackId, volume: clampedVolume)
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "muteTrack":
                guard let project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                let muted = params["muted"]?.boolValue ?? true
                
                // Update audio engine (handles model + audio + notification)
                audioEngine?.updateTrackMute(trackId: trackId, isMuted: muted)
                
                if let track = project.tracks.first(where: { $0.id == trackId }) {
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "soloTrack":
                guard let project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                let soloed = params["soloed"]?.boolValue ?? true
                
                // Update audio engine (handles model + audio + notification)
                audioEngine?.updateTrackSolo(trackId: trackId, isSolo: soloed)
                
                if let track = project.tracks.first(where: { $0.id == trackId }) {
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "setTrackPan":
                guard let project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                let pan = params["pan"]?.doubleValue ?? 0.5
                let clampedPan = Float(max(0, min(1, pan)))
                
                // Update audio engine (handles model + audio + notification)
                audioEngine?.updateTrackPan(trackId: trackId, pan: clampedPan)
                
                if let track = project.tracks.first(where: { $0.id == trackId }) {
                    let panPercent = Int((clampedPan - 0.5) * 200) // -100 (left) to +100 (right)
                    let panDirection = panPercent < 0 ? "L" : "R"
                    let panDisplay = panPercent == 0 ? "Center" : "\(abs(panPercent))\(panDirection)"
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "setTrackName":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                guard let newName = params["name"]?.stringValue else {
                    throw AICommandError.invalidParameter("name")
                }
                
                if let index = project.tracks.firstIndex(where: { $0.id == trackId }) {
                    project.tracks[index].name = newName
                    projectManager.currentProject = project
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "setTrackColor":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                guard let colorString = params["color"]?.stringValue else {
                    throw AICommandError.invalidParameter("color")
                }
                
                // Map color string to TrackColor enum
                let trackColor: TrackColor
                switch colorString.lowercased() {
                case "blue": trackColor = .blue
                case "red": trackColor = .red
                case "green": trackColor = .green
                case "yellow": trackColor = .yellow
                case "purple": trackColor = .purple
                case "pink": trackColor = .pink
                case "orange": trackColor = .orange
                case "teal": trackColor = .teal
                case "indigo": trackColor = .indigo
                case "gray": trackColor = .gray
                case "brown": trackColor = .custom("#8B4513") // Brown custom color
                default:
                    throw AICommandError.invalidParameter("color - must be one of: red, orange, yellow, green, blue, purple, pink, teal, indigo, gray, brown")
                }
                
                if let index = project.tracks.firstIndex(where: { $0.id == trackId }) {
                    project.tracks[index].color = trackColor
                    projectManager.currentProject = project
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "setTrackIcon":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                guard let iconName = params["icon"]?.stringValue else {
                    throw AICommandError.invalidParameter("icon")
                }
                
                if let index = project.tracks.firstIndex(where: { $0.id == trackId }) {
                    project.tracks[index].iconName = iconName
                    projectManager.currentProject = project
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            // MARK: Region Tools
            // MARK: Playback Tools
            case "play":
                audioEngine?.play()
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "stop":
                audioEngine?.stop()
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "setPlayhead":
                guard let beat = params["beat"]?.doubleValue else {
                    throw AICommandError.invalidParameter("beat")
                }
                audioEngine?.seek(toBeat: beat)
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            // MARK: Region Tools
            case "addMidiRegion":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                
                let trackIdStr = params["trackId"]?.stringValue
                
                guard let trackIdStr = trackIdStr,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                
                let name = params["name"]?.stringValue ?? "Region"
                // Backend may send startBeat/durationBeats as string ("0", "16") or number
                let startBeat = doubleFromParam(params["startBeat"]) ?? 0
                let durationBeats = doubleFromParam(params["durationBeats"]) ?? 4
                let endBeat = startBeat + durationBeats
                
                
                // Check for overlapping regions
                if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
                    let track = project.tracks[trackIndex]
                    
                    // Check MIDI regions for overlap
                    for existingRegion in track.midiRegions {
                        let existingStart = existingRegion.startTime
                        let existingEnd = existingStart + existingRegion.duration
                        
                        // Check if regions overlap
                        if startBeat < existingEnd && endBeat > existingStart {
                            let errorMsg = "A region already exists at beat \(Int(startBeat))-\(Int(endBeat)) on track '\(track.name)'. The existing region '\(existingRegion.name)' spans beat \(Int(existingStart))-\(Int(existingEnd))."
                            return ToolExecutionResult(
                                tool: tool,
                                success: false,
                                data: [:],
                                error: errorMsg
                            )
                        }
                    }
                    
                    // Check audio regions for overlap too
                    for existingRegion in track.regions {
                        let existingStart = existingRegion.startBeat
                        let existingEnd = existingStart + existingRegion.durationBeats
                        
                        if startBeat < existingEnd && endBeat > existingStart {
                            let errorMsg = "An audio region already exists at beat \(Int(startBeat))-\(Int(endBeat)) on track '\(track.name)'."
                            return ToolExecutionResult(
                                tool: tool,
                                success: false,
                                data: [:],
                                error: errorMsg
                            )
                        }
                    }
                    
                    // Entity ID contract (SWIFT_INTEGRATION.md): backend sends regionId; we must use it so later tools (add_notes, etc.) find this region.
                    guard let regionIdStr = params["regionId"]?.stringValue,
                          let regionId = UUID(uuidString: regionIdStr) else {
                        throw AICommandError.invalidParameter("regionId (required; backend must send region UUID for addMidiRegion)")
                    }
                    
                    // No overlap - create the region
                    let region = MIDIRegion(
                        id: regionId,
                        name: name,
                        notes: [],
                        startTime: startBeat,
                        duration: durationBeats,
                        instrumentId: nil,
                        color: .blue,
                        isLooped: false,
                        loopCount: 1,
                        isMuted: false,
                        controllerEvents: [],
                        pitchBendEvents: [],
                        contentLength: durationBeats
                    )
                    
                    project.tracks[trackIndex].midiRegions.append(region)
                    projectManager.currentProject = project
                    
                    return ToolExecutionResult(
                        tool: tool,
                        success: true,
                        data: [
                            "regionId": region.id.uuidString,
                            "trackId": trackId.uuidString,
                            "startBeat": String(startBeat),
                            "durationBeats": String(durationBeats)
                        ],
                        error: nil
                    )
                } else {
                    let availableTrackInfo = project.tracks.map { "'\($0.name)' (ID: \($0.id.uuidString))" }.joined(separator: ", ")
                    let errorMsg = "Track '\(trackId.uuidString)' not found. Available tracks: \(availableTrackInfo)"
                    return ToolExecutionResult(
                        tool: tool,
                        success: false,
                        data: [:],
                        error: errorMsg
                    )
                }
                
            case "moveRegion":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let regionIdStr = params["regionId"]?.stringValue,
                      let regionId = UUID(uuidString: regionIdStr) else {
                    throw AICommandError.invalidParameter("regionId")
                }
                guard let newStartBeat = params["startBeat"]?.doubleValue else {
                    throw AICommandError.invalidParameter("startBeat")
                }
                
                // Find and move the region
                var found = false
                for trackIndex in project.tracks.indices {
                    if let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                        let oldStart = project.tracks[trackIndex].midiRegions[regionIndex].startTime
                        project.tracks[trackIndex].midiRegions[regionIndex].startTime = newStartBeat
                        projectManager.currentProject = project
                        found = true
                        break
                    }
                }
                
                if !found {
                    throw AICommandError.regionNotFound(regionId)
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "deleteRegion":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let regionIdStr = params["regionId"]?.stringValue,
                      let regionId = UUID(uuidString: regionIdStr) else {
                    throw AICommandError.invalidParameter("regionId")
                }
                
                // Find and delete the region
                var found = false
                for trackIndex in project.tracks.indices {
                    if let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                        let regionName = project.tracks[trackIndex].midiRegions[regionIndex].name
                        project.tracks[trackIndex].midiRegions.remove(at: regionIndex)
                        projectManager.currentProject = project
                        found = true
                        break
                    }
                }
                
                if !found {
                    throw AICommandError.regionNotFound(regionId)
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "duplicateRegion":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let regionIdStr = params["regionId"]?.stringValue,
                      let regionId = UUID(uuidString: regionIdStr) else {
                    throw AICommandError.invalidParameter("regionId")
                }
                
                // Optional: offset for the duplicated region (defaults to placing after original)
                let offset = params["offset"]?.doubleValue
                
                // Find and duplicate the region
                var newRegionId: UUID?
                for trackIndex in project.tracks.indices {
                    if let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                        let original = project.tracks[trackIndex].midiRegions[regionIndex]
                        
                        // Calculate new start position
                        let newStart: Double
                        if let off = offset {
                            newStart = original.startTime + off
                        } else {
                            // Default: place immediately after the original
                            newStart = original.startTime + original.duration
                        }
                        
                        // Create duplicate with new ID
                        var duplicate = MIDIRegion(
                            id: UUID(),
                            name: "\(original.name) Copy",
                            notes: original.notes.map { note in
                                MIDINote(
                                    id: UUID(),
                                    pitch: note.pitch,
                                    velocity: note.velocity,
                                    startTime: note.startTime,
                                    duration: note.duration,
                                    channel: note.channel
                                )
                            },
                            startTime: newStart,
                            duration: original.duration,
                            instrumentId: original.instrumentId,
                            color: original.color,
                            isLooped: original.isLooped,
                            loopCount: original.loopCount,
                            isMuted: original.isMuted,
                            controllerEvents: original.controllerEvents,
                            pitchBendEvents: original.pitchBendEvents,
                            contentLength: original.contentLength
                        )
                        
                        newRegionId = duplicate.id
                        project.tracks[trackIndex].midiRegions.append(duplicate)
                        projectManager.currentProject = project
                        break
                    }
                }
                
                guard let createdId = newRegionId else {
                    throw AICommandError.regionNotFound(regionId)
                }
                
                return ToolExecutionResult(
                    tool: tool,
                    success: true,
                    data: ["regionId": createdId.uuidString],
                    error: nil
                )
                
            case "clearNotes":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let regionIdStr = params["regionId"]?.stringValue,
                      let regionId = UUID(uuidString: regionIdStr) else {
                    throw AICommandError.invalidParameter("regionId")
                }
                
                // Find and clear notes from the region
                var found = false
                for trackIndex in project.tracks.indices {
                    if let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                        let noteCount = project.tracks[trackIndex].midiRegions[regionIndex].notes.count
                        project.tracks[trackIndex].midiRegions[regionIndex].notes.removeAll()
                        projectManager.currentProject = project
                        found = true
                        break
                    }
                }
                
                if !found {
                    throw AICommandError.regionNotFound(regionId)
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "addNotes":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                
                let regionIdStr = params["regionId"]?.stringValue
                
                guard let regionIdStr = regionIdStr,
                      let regionId = UUID(uuidString: regionIdStr) else {
                    throw AICommandError.invalidParameter("regionId")
                }
                
                // Try to get notes array - handle both direct array and JSON string
                var notesArray: [AnyCodableValue]? = params["notes"]?.arrayValue
                
                // Fallback: if notes is a JSON string, parse it
                if notesArray == nil, let notesStr = params["notes"]?.stringValue {
                    if let data = notesStr.data(using: .utf8) {
                        do {
                            let json = try JSONSerialization.jsonObject(with: data)
                            
                            // Handle {"notes": [...]} wrapper
                            if let dict = json as? [String: Any], let notes = dict["notes"] as? [[String: Any]] {
                                notesArray = notes.map { noteDict in
                                    var codableDict: [String: AnyCodableValue] = [:]
                                    for (key, value) in noteDict {
                                        if let intVal = value as? Int {
                                            codableDict[key] = .int(intVal)
                                        } else if let doubleVal = value as? Double {
                                            codableDict[key] = .double(doubleVal)
                                        } else if let stringVal = value as? String {
                                            codableDict[key] = .string(stringVal)
                                        }
                                    }
                                    return .dictionary(codableDict)
                                }
                            }
                            // Handle direct array
                            else if let notes = json as? [[String: Any]] {
                                notesArray = notes.map { noteDict in
                                    var codableDict: [String: AnyCodableValue] = [:]
                                    for (key, value) in noteDict {
                                        if let intVal = value as? Int {
                                            codableDict[key] = .int(intVal)
                                        } else if let doubleVal = value as? Double {
                                            codableDict[key] = .double(doubleVal)
                                        } else if let stringVal = value as? String {
                                            codableDict[key] = .string(stringVal)
                                        }
                                    }
                                    return .dictionary(codableDict)
                                }
                            }
                        } catch {
                        }
                    }
                }
                
                guard let notesArray = notesArray else {
                    throw AICommandError.invalidParameter("notes")
                }
                
                
                // Parse notes
                var midiNotes: [MIDINote] = []
                for noteValue in notesArray {
                    if let noteDict = noteValue.dictionaryValue {
                        let pitch = noteDict["pitch"]?.intValue ?? 60
                        let velocity = noteDict["velocity"]?.intValue ?? 100
                        let startBeat = noteDict["startBeat"]?.doubleValue ?? 0
                        let duration = noteDict["duration"]?.doubleValue ?? 1
                        
                        let note = MIDINote(
                            id: UUID(),
                            pitch: UInt8(clamping: pitch),
                            velocity: UInt8(clamping: velocity),
                            startTime: startBeat,
                            duration: duration,
                            channel: 0
                        )
                        midiNotes.append(note)
                    }
                }
                
                // Find and update the region
                var foundRegion = false
                for trackIndex in project.tracks.indices {
                    if let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                        project.tracks[trackIndex].midiRegions[regionIndex].notes.append(contentsOf: midiNotes)
                        
                        // Only expand region if notes extend beyond current duration — never shrink
                        let allNotes = project.tracks[trackIndex].midiRegions[regionIndex].notes
                        let currentDuration = project.tracks[trackIndex].midiRegions[regionIndex].duration
                        if let lastNoteEnd = allNotes.map({ $0.startTime + $0.duration }).max() {
                            // Only expand if notes actually extend beyond the current region
                            if lastNoteEnd > currentDuration {
                                // Add small padding and round up to nearest bar (4 beats)
                                let paddedEnd = lastNoteEnd + 0.5
                                let fittedDuration = ceil(paddedEnd / 4.0) * 4.0
                                project.tracks[trackIndex].midiRegions[regionIndex].duration = fittedDuration
                                project.tracks[trackIndex].midiRegions[regionIndex].contentLength = fittedDuration
                            } else {
                            }
                        }
                        
                        projectManager.currentProject = project
                        foundRegion = true
                        let finalRegion = project.tracks[trackIndex].midiRegions[regionIndex]
                        break
                    }
                }
                
                if !foundRegion {
                    for (ti, track) in project.tracks.enumerated() {
                    }
                    return ToolExecutionResult(
                        tool: tool,
                        success: false,
                        data: [:],
                        error: "Region not found: \(regionId)"
                    )
                }
                
                return ToolExecutionResult(
                    tool: tool,
                    success: true,
                    data: ["noteCount": String(midiNotes.count)],
                    error: nil
                )
                
            // MARK: Effect Tools
            case "addInsertEffect":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                guard let effectTypeStr = params["type"]?.stringValue else {
                    throw AICommandError.invalidParameter("type")
                }
                
                guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
                    throw AICommandError.custom("Track not found")
                }
                
                // Get current slot index
                let slotIndex = project.tracks[trackIndex].pluginConfigs.count
                
                // Create plugin configuration from effect type
                guard let pluginConfig = EffectTypeMapping.createPluginConfig(
                    effectType: effectTypeStr,
                    slotIndex: slotIndex
                ) else {
                    throw AICommandError.custom("Unknown effect type: \(effectTypeStr)")
                }
                
                // Add to track's plugin configs
                project.tracks[trackIndex].pluginConfigs.append(pluginConfig)
                projectManager.currentProject = project
                
                // Trigger plugin loading in audio engine
                if let engine = audioEngine {
                    await engine.restorePluginsFromProject()
                }
                
                return ToolExecutionResult(
                    tool: tool,
                    success: true,
                    data: ["pluginIndex": String(slotIndex), "pluginName": pluginConfig.pluginName],
                    error: nil
                )
                
            // MARK: Bus Tools
            case "ensureBus":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                
                let name = params["name"]?.stringValue ?? "Bus"
                let outputLevel = params["outputLevel"]?.doubleValue ?? 0.7
                
                // Check if bus already exists
                if let existingBus = project.buses.first(where: { $0.name == name }) {
                    return ToolExecutionResult(
                        tool: tool,
                        success: true,
                        data: ["busId": existingBus.id.uuidString],
                        error: nil
                    )
                }
                
                // Create new bus
                var bus = MixerBus(name: name)
                bus.outputLevel = outputLevel
                
                // Add plugins to bus if provided (using same mapping as tracks)
                if let effectsArray = params["effects"]?.arrayValue {
                    for (index, effectValue) in effectsArray.enumerated() {
                        if let effectDict = effectValue.dictionaryValue,
                           let typeStr = effectDict["type"]?.stringValue {
                            if let pluginConfig = EffectTypeMapping.createPluginConfig(
                                effectType: typeStr,
                                slotIndex: index
                            ) {
                                bus.pluginConfigs.append(pluginConfig)
                            }
                        }
                    }
                }
                
                project.buses.append(bus)
                projectManager.currentProject = project
                
                return ToolExecutionResult(
                    tool: tool,
                    success: true,
                    data: ["busId": bus.id.uuidString],
                    error: nil
                )
                
            case "addSend":
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                guard let busName = params["busName"]?.stringValue else {
                    throw AICommandError.invalidParameter("busName")
                }
                
                let sendLevel = params["sendLevel"]?.doubleValue ?? 0.3
                
                // Find the bus
                guard let bus = project.buses.first(where: { $0.name == busName }) else {
                    throw AICommandError.busNotFound(busName)
                }
                
                let send = TrackSend(busId: bus.id, sendLevel: sendLevel)
                
                if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
                    project.tracks[trackIndex].sends.append(send)
                    projectManager.currentProject = project
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "addAutomation":
                // Add automation points to a track's automation lane
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let trackIdStr = params["trackId"]?.stringValue,
                      let trackId = UUID(uuidString: trackIdStr) else {
                    throw AICommandError.invalidParameter("trackId")
                }
                guard let parameterName = params["parameter"]?.stringValue else {
                    throw AICommandError.invalidParameter("parameter")
                }
                guard let pointsArray = params["points"]?.arrayValue else {
                    throw AICommandError.invalidParameter("points")
                }
                
                // Map parameter name to AutomationParameter
                guard let automationParam = AutomationParameter(rawValue: parameterName) else {
                    throw AICommandError.invalidParameter("parameter")
                }
                
                // Parse automation points
                var automationPoints: [AutomationPoint] = []
                for pointValue in pointsArray {
                    guard let pointDict = pointValue.dictionaryValue else { continue }
                    let beat = pointDict["beat"]?.doubleValue ?? 0
                    let value = pointDict["value"]?.doubleValue ?? 0.5
                    let curveRaw = pointDict["curve"]?.stringValue ?? "linear"
                    let curveType = CurveType(rawValue: curveRaw) ?? .linear
                    
                    automationPoints.append(AutomationPoint(beat: beat, value: Float(value), curve: curveType))
                }
                
                if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
                    // Hide all other lanes first (only one automation parameter visible at a time)
                    for i in 0..<project.tracks[trackIndex].automationLanes.count {
                        project.tracks[trackIndex].automationLanes[i].isVisible = false
                    }
                    
                    // Find or create the automation lane
                    if let laneIndex = project.tracks[trackIndex].automationLanes.firstIndex(where: { $0.parameter == automationParam }) {
                        // Add points to existing lane and make it visible
                        project.tracks[trackIndex].automationLanes[laneIndex].points.append(contentsOf: automationPoints)
                        project.tracks[trackIndex].automationLanes[laneIndex].points.sort { $0.beat < $1.beat }
                        project.tracks[trackIndex].automationLanes[laneIndex].isVisible = true
                    } else {
                        // Create new lane with points (visible by default)
                        var newLane = AutomationLane(parameter: automationParam, color: automationParam.color)
                        newLane.points = automationPoints
                        newLane.isVisible = true
                        project.tracks[trackIndex].automationLanes.append(newLane)
                    }
                    
                    // Expand automation view
                    project.tracks[trackIndex].automationExpanded = true
                    projectManager.currentProject = project
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "addPitchBend":
                // Add pitch bend events to a MIDI region
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let regionIdStr = params["regionId"]?.stringValue,
                      let regionId = UUID(uuidString: regionIdStr) else {
                    throw AICommandError.invalidParameter("regionId")
                }
                guard let eventsArray = params["events"]?.arrayValue else {
                    throw AICommandError.invalidParameter("events")
                }
                
                // Parse pitch bend events
                var pitchBendEvents: [MIDIPitchBendEvent] = []
                for eventValue in eventsArray {
                    guard let eventDict = eventValue.dictionaryValue else { continue }
                    let time = eventDict["time"]?.doubleValue ?? 0
                    let value = eventDict["value"]?.intValue ?? 0  // -8192 to 8191
                    let channel = eventDict["channel"]?.intValue ?? 0
                    
                    pitchBendEvents.append(MIDIPitchBendEvent(
                        value: Int16(clamping: value),
                        time: time,
                        channel: UInt8(clamping: channel)
                    ))
                }
                
                // Find and update the region
                for trackIndex in project.tracks.indices {
                    if let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                        project.tracks[trackIndex].midiRegions[regionIndex].pitchBendEvents.append(contentsOf: pitchBendEvents)
                        project.tracks[trackIndex].midiRegions[regionIndex].pitchBendEvents.sort { $0.time < $1.time }
                        projectManager.currentProject = project
                        break
                    }
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "applySwing":
                // Apply swing to notes in a region
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let regionIdStr = params["regionId"]?.stringValue,
                      let regionId = UUID(uuidString: regionIdStr) else {
                    throw AICommandError.invalidParameter("regionId")
                }
                
                let amount = Float(params["amount"]?.doubleValue ?? 0.2)  // Default 20% swing
                let gridResolution = SnapResolution.eighth  // Default to eighth notes
                
                // Find and update the region
                for trackIndex in project.tracks.indices {
                    if let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                        let originalNotes = project.tracks[trackIndex].midiRegions[regionIndex].notes
                        let swungNotes = QuantizationEngine.applySwing(
                            notes: originalNotes,
                            amount: amount,
                            gridResolution: gridResolution
                        )
                        project.tracks[trackIndex].midiRegions[regionIndex].notes = swungNotes
                        projectManager.currentProject = project
                        break
                    }
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "quantizeNotes":
                // Quantize notes in a region to a grid
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let regionIdStr = params["regionId"]?.stringValue,
                      let regionId = UUID(uuidString: regionIdStr) else {
                    throw AICommandError.invalidParameter("regionId")
                }
                
                // Parse grid size (in beats) and convert to SnapResolution
                let gridSize = params["gridSize"]?.doubleValue ?? 0.25  // Default to sixteenth notes
                let resolution: SnapResolution
                switch gridSize {
                case 0.125: resolution = .thirtysecond
                case 0.25: resolution = .sixteenth
                case 0.5: resolution = .eighth
                case 1.0: resolution = .quarter
                case 2.0: resolution = .half
                case 4.0: resolution = .bar
                default: resolution = .sixteenth
                }
                
                let strength = Float(params["strength"]?.doubleValue ?? 1.0)  // Full quantize by default
                
                // Find and update the region
                for trackIndex in project.tracks.indices {
                    if let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                        let originalNotes = project.tracks[trackIndex].midiRegions[regionIndex].notes
                        let quantizedNotes = QuantizationEngine.quantize(
                            notes: originalNotes,
                            resolution: resolution,
                            strength: strength,
                            quantizeDuration: true
                        )
                        project.tracks[trackIndex].midiRegions[regionIndex].notes = quantizedNotes
                        projectManager.currentProject = project
                        break
                    }
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "addMidiCc":
                // Add MIDI CC events to a region (Mod Wheel, Expression, etc.)
                guard var project = projectManager.currentProject else {
                    throw AICommandError.noProject
                }
                guard let regionIdStr = params["regionId"]?.stringValue,
                      let regionId = UUID(uuidString: regionIdStr) else {
                    throw AICommandError.invalidParameter("regionId")
                }
                guard let eventsArray = params["events"]?.arrayValue else {
                    throw AICommandError.invalidParameter("events")
                }
                
                // Parse CC events
                var ccEvents: [MIDICCEvent] = []
                for eventValue in eventsArray {
                    guard let eventDict = eventValue.dictionaryValue else { continue }
                    let controller = eventDict["controller"]?.intValue ?? 1  // Default to mod wheel
                    let value = eventDict["value"]?.intValue ?? 64
                    let time = eventDict["time"]?.doubleValue ?? 0
                    let channel = eventDict["channel"]?.intValue ?? 0
                    
                    ccEvents.append(MIDICCEvent(
                        id: UUID(),
                        controller: UInt8(clamping: controller),
                        value: UInt8(clamping: value),
                        time: time,
                        channel: UInt8(clamping: channel)
                    ))
                }
                
                // Find and update the region
                for trackIndex in project.tracks.indices {
                    if let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                        project.tracks[trackIndex].midiRegions[regionIndex].controllerEvents.append(contentsOf: ccEvents)
                        project.tracks[trackIndex].midiRegions[regionIndex].controllerEvents.sort { $0.time < $1.time }
                        projectManager.currentProject = project
                        break
                    }
                }
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            // MARK: UI State Tools
                
            case "setZoom":
                let horizontal = params["horizontal"]?.doubleValue
                let vertical = params["vertical"]?.doubleValue
                
                // Update project state for persistence
                if var project = projectManager.currentProject {
                    if let h = horizontal {
                        project.uiState.horizontalZoom = h
                    }
                    if let v = vertical {
                        project.uiState.verticalZoom = v
                    }
                    projectManager.currentProject = project
                }
                
                // UI reads directly from project.uiState - no callback needed
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "setTimelineOptions":
                let timeDisplayMode = params["timeDisplayMode"]?.stringValue
                let snapToGrid = params["snapToGrid"]?.boolValue
                let catchPlayheadEnabled = params["catchPlayheadEnabled"]?.boolValue
                
                // Update project state for persistence
                if var project = projectManager.currentProject {
                    if let mode = timeDisplayMode {
                        project.uiState.timeDisplayMode = mode
                    }
                    if let snap = snapToGrid {
                        project.uiState.snapToGrid = snap
                    }
                    if let catchPlayhead = catchPlayheadEnabled {
                        project.uiState.catchPlayheadEnabled = catchPlayhead
                    }
                    projectManager.currentProject = project
                }
                
                // UI reads directly from project.uiState - no callback needed
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "setMetronome":
                let enabled = params["enabled"]?.boolValue
                let volume = params["volume"]?.doubleValue.map { Float($0) }
                
                // Update project state for persistence
                if var project = projectManager.currentProject {
                    if let e = enabled {
                        project.uiState.metronomeEnabled = e
                    }
                    if let v = volume {
                        project.uiState.metronomeVolume = v
                    }
                    projectManager.currentProject = project
                }
                
                // UI reads directly from project.uiState - no callback needed
                // Note: MetronomeEngine needs separate sync via restoreUIState on project load
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "showPanel":
                guard let panel = params["panel"]?.stringValue,
                      let visible = params["visible"]?.boolValue else {
                    throw AICommandError.invalidParameter("panel, visible")
                }
                
                // Update project state for persistence
                if var project = projectManager.currentProject {
                    // Bottom panels are mutually exclusive - close others when opening one
                    let bottomPanels = ["mixer", "stepSequencer", "pianoRoll", "synthesizer"]
                    let isBottomPanel = bottomPanels.contains(panel)
                    
                    if isBottomPanel && visible {
                        // Close all other bottom panels first
                        project.uiState.showingMixer = false
                        project.uiState.showingStepSequencer = false
                        project.uiState.showingPianoRoll = false
                        project.uiState.showingSynthesizer = false
                    }
                    
                    switch panel {
                    case "inspector":
                        project.uiState.showingInspector = visible
                    case "mixer":
                        project.uiState.showingMixer = visible
                    case "stepSequencer":
                        project.uiState.showingStepSequencer = visible
                    case "pianoRoll":
                        project.uiState.showingPianoRoll = visible
                    case "synthesizer":
                        project.uiState.showingSynthesizer = visible
                    default:
                        throw AICommandError.invalidParameter("panel: \(panel)")
                    }
                    projectManager.currentProject = project
                }
                
                // UI reads directly from project.uiState - no callback needed
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "setPanelSize":
                guard let panel = params["panel"]?.stringValue,
                      let size = params["size"]?.doubleValue else {
                    throw AICommandError.invalidParameter("panel, size")
                }
                
                // Update project state for persistence with clamped values
                if var project = projectManager.currentProject {
                    switch panel {
                    case "inspector":
                        // Inspector width: 250-500
                        project.uiState.inspectorWidth = max(250, min(500, size))
                    case "mixer":
                        // Bottom panels max 450px to leave room for timeline + control bar
                        project.uiState.mixerHeight = max(200, min(450, size))
                    case "stepSequencer":
                        project.uiState.stepSequencerHeight = max(200, min(450, size))
                    case "pianoRoll":
                        project.uiState.pianoRollHeight = max(250, min(450, size))
                    case "synthesizer":
                        project.uiState.synthesizerHeight = max(200, min(450, size))
                    default:
                        throw AICommandError.invalidParameter("panel: \(panel)")
                    }
                    projectManager.currentProject = project
                }
                
                // UI reads directly from project.uiState - no callback needed
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "selectTab":
                let tab = params["tab"]?.stringValue
                let editorMode = params["editorMode"]?.stringValue
                
                // Update project state for persistence
                if var project = projectManager.currentProject {
                    if let t = tab {
                        project.uiState.selectedInspectorTab = t
                    }
                    if let mode = editorMode {
                        project.uiState.selectedEditorMode = mode
                    }
                    projectManager.currentProject = project
                }
                
                // UI reads directly from project.uiState - no callback needed
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "seekPlayhead":
                guard let beat = params["beat"]?.doubleValue else {
                    throw NSError(domain: "AICommandDispatcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing required parameter: beat"])
                }
                
                // Seek the audio engine
                audioEngine?.seek(toBeat: beat)
                
                return ToolExecutionResult(tool: tool, success: true, data: [:], error: nil)
                
            case "getUiState":
                guard let project = projectManager.currentProject else {
                    throw NSError(domain: "AICommandDispatcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "No project loaded"])
                }
                
                // Return current UI state from project
                let uiStateData: [String: String] = [
                    "horizontalZoom": String(project.uiState.horizontalZoom),
                    "verticalZoom": String(project.uiState.verticalZoom),
                    "timeDisplayMode": project.uiState.timeDisplayMode,
                    "snapToGrid": String(project.uiState.snapToGrid),
                    "metronomeEnabled": String(project.uiState.metronomeEnabled),
                    "showingInspector": String(project.uiState.showingInspector),
                    "showingMixer": String(project.uiState.showingMixer),
                    "playheadPosition": String(project.uiState.playheadPosition)
                ]
                
                return ToolExecutionResult(tool: tool, success: true, data: uiStateData, error: nil)
                
            default:
                return ToolExecutionResult(
                    tool: tool,
                    success: false,
                    data: [:],
                    error: "Unknown tool: \(tool)"
                )
            }
            
        } catch {
            return ToolExecutionResult(
                tool: tool,
                success: false,
                data: [:],
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - MCP Tool Name Normalization
    
    /// Convert MCP-style tool names to internal camelCase format
    /// Examples:
    /// - stori_add_midi_track -> addMidiTrack
    /// - stori_create_project -> createProject
    /// - addMidiTrack -> addMidiTrack (pass-through)
    private func normalizeMCPToolName(_ tool: String) -> String {
        // If already in camelCase (no stori_ prefix), return as-is
        guard tool.hasPrefix("stori_") else {
            return tool
        }
        
        // Remove stori_ prefix
        let withoutPrefix = tool.dropFirst(6) // "stori_".count
        
        // Convert snake_case to camelCase
        let components = withoutPrefix.split(separator: "_")
        guard let first = components.first else {
            return tool // Malformed, return original
        }
        
        let camelCase = components.dropFirst().reduce(String(first)) { result, component in
            result + component.prefix(1).uppercased() + component.dropFirst()
        }
        
        return camelCase
    }
    
    // MARK: - Validation
    
    /// Defense-in-depth validation for tool parameters.
    /// Backend should send fully-resolved, validated params, but we double-check.
    private func validateToolParams(_ tool: String, _ params: [String: AnyCodableValue]) -> String? {
        if let trackId = params["trackId"]?.stringValue {
            if trackId.hasPrefix("$") {
                return "Received unresolved variable reference for trackId. Backend should resolve all variables."
            }
            guard let trackUUID = UUID(uuidString: trackId) else {
                return "Invalid trackId format"
            }
            // M-12: Validate track exists in project
            if let project = projectManager?.currentProject, !project.tracks.contains(where: { $0.id == trackUUID }) {
                return "Track not found in project"
            }
        }
        if let regionId = params["regionId"]?.stringValue {
            if regionId.hasPrefix("$") {
                return "Received unresolved variable reference for regionId. Backend should resolve all variables."
            }
            guard let regionUUID = UUID(uuidString: regionId) else {
                return "Invalid regionId format"
            }
            // M-12: Validate region exists in project
            if let project = projectManager?.currentProject {
                let allMidiRegions = project.tracks.flatMap(\.midiRegions)
                if !allMidiRegions.contains(where: { $0.id == regionUUID }) {
                    return "Region not found in project"
                }
            }
        }
        // M-12: Content validation for addMidiNotes
        if tool == "addMidiNotes" || tool == "add_midi_notes" {
            guard let notes = params["notes"]?.arrayValue else {
                return "Missing notes array"
            }
            for note in notes {
                guard let dict = note.dictionaryValue else { continue }
                if let pitch = dict["pitch"]?.intValue, (pitch < 0 || pitch > 127) {
                    return "Invalid note pitch (0-127)"
                }
                if let vel = dict["velocity"]?.intValue, (vel < 0 || vel > 127) {
                    return "Invalid note velocity (0-127)"
                }
                if let dur = dict["duration"]?.doubleValue, (dur <= 0 || dur >= 1000) {
                    return "Invalid note duration"
                }
            }
        }
        if tool == "setTrackVolume" || tool == "set_track_volume" {
            if let vol = params["volume"]?.doubleValue, (vol < 0 || vol > 1.5) {
                return "Volume must be 0.0 to 1.5"
            }
        }
        // M-4: Strict range validation for common tools
        if tool == "setTempo" || tool.contains("tempo") {
            if let bpm = params["tempo"]?.doubleValue, bpm < 20 || bpm > 300 {
                return "Tempo must be between 20 and 300 BPM"
            }
        }
        if tool == "setTrackPan" || tool == "set_track_pan" {
            if let pan = params["pan"]?.doubleValue, pan < 0 || pan > 1 {
                return "Pan must be between 0.0 and 1.0"
            }
        }
        if tool == "setPlayhead" || tool.contains("playhead") {
            if let beat = params["beat"]?.doubleValue, beat < 0 {
                return "Playhead beat must be non-negative"
            }
        }
        if tool == "createProject" || tool == "create_project" {
            if let name = params["name"]?.stringValue, name.count > 200 {
                return "Project name must be 200 characters or less"
            }
            if let bpm = params["tempo"]?.doubleValue, (bpm < 20 || bpm > 300) {
                return "Tempo must be between 20 and 300 BPM"
            }
        }
        if tool == "setTrackName" || tool == "set_track_name" {
            if let name = params["name"]?.stringValue, name.count > 256 {
                return "Track name must be 256 characters or less"
            }
        }
        // M-4: Cap note count for addMidiNotes
        if tool == "addMidiNotes" || tool == "add_midi_notes" {
            if let notes = params["notes"]?.arrayValue, notes.count > 10_000 {
                return "Note count exceeds maximum (10,000)"
            }
        }
        return nil
    }
    
    // MARK: - Helpers
    
    private func parseTrackColor(_ name: String) -> TrackColor {
        switch name.lowercased() {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "teal": return .teal
        case "indigo": return .indigo
        case "gray": return .gray
        default:
            if name.hasPrefix("#") {
                return .custom(name)
            }
            return .blue
        }
    }
    
    private func gmProgramName(_ program: Int) -> String {
        let names = [
            "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano", "Honky-tonk Piano",
            "Electric Piano 1", "Electric Piano 2", "Harpsichord", "Clavinet",
            "Celesta", "Glockenspiel", "Music Box", "Vibraphone",
            "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
            "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ",
            "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
            "Acoustic Guitar (nylon)", "Acoustic Guitar (steel)", "Electric Guitar (jazz)", "Electric Guitar (clean)",
            "Electric Guitar (muted)", "Overdriven Guitar", "Distortion Guitar", "Guitar Harmonics",
            "Acoustic Bass", "Electric Bass (finger)", "Electric Bass (pick)", "Fretless Bass",
            "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2"
        ]
        
        if program >= 0 && program < names.count {
            return names[program]
        }
        return "Program \(program)"
    }
}

// MARK: - Errors

enum AICommandError: Error, LocalizedError {
    case noProject
    case trackNotFound(UUID)
    case regionNotFound(UUID)
    case busNotFound(String)
    case invalidParameter(String)
    case unknownTool(String)
    case custom(String)
    
    var errorDescription: String? {
        switch self {
        case .noProject:
            return "No project is currently open"
        case .trackNotFound(let id):
            return "Track not found: \(id)"
        case .regionNotFound(let id):
            return "Region not found: \(id)"
        case .custom(let message):
            return message
        case .busNotFound(let name):
            return "Bus not found: \(name)"
        case .invalidParameter(let param):
            return "Invalid or missing parameter: \(param)"
        case .unknownTool(let tool):
            return "Unknown tool: \(tool)"
        }
    }
}
