//
//  AudioEngineDiagnostics.swift
//  Stori
//
//  Comprehensive diagnostic tool for audio engine debugging.
//  Dumps complete engine state for troubleshooting.
//

//  NOTE: @preconcurrency import must be the first import of that module in this file (Swift compiler limitation).
@preconcurrency import AVFoundation
import Foundation

// MARK: - Audio Engine Diagnostics

/// Comprehensive diagnostic reporting for audio engine state.
/// Use this when users report issues to get complete system information.
@MainActor
struct AudioEngineDiagnostics {
    
    // MARK: - Report Generation
    
    /// Generate a comprehensive diagnostic report.
    /// Returns markdown-formatted text suitable for bug reports.
    static func generateReport(
        engine: AVAudioEngine,
        graphFormat: AVAudioFormat?,
        trackNodes: [UUID: TrackAudioNode],
        busNodes: [UUID: BusAudioNode],
        currentProject: AudioProject?,
        healthMonitor: AudioEngineHealthMonitor,
        errorTracker: AudioEngineErrorTracker,
        performanceMonitor: AudioPerformanceMonitor
    ) -> String {
        var report = """
        # Stori Audio Engine Diagnostic Report
        Generated: \(Date())
        
        ---
        
        ## System Information
        
        """
        
        // macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        report += "- **OS Version**: \(osVersion)\n"
        
        // Audio hardware
        let hardwareFormat = engine.outputNode.inputFormat(forBus: 0)
        report += "- **Hardware Sample Rate**: \(Int(hardwareFormat.sampleRate))Hz\n"
        report += "- **Hardware Channels**: \(hardwareFormat.channelCount)\n"
        
        // Graph format
        if let graphFormat = graphFormat {
            report += "- **Graph Sample Rate**: \(Int(graphFormat.sampleRate))Hz\n"
            report += "- **Graph Channels**: \(graphFormat.channelCount)\n"
            
            // Check for mismatch
            if abs(graphFormat.sampleRate - hardwareFormat.sampleRate) > 1.0 {
                report += "  - ⚠️ **MISMATCH**: Graph and hardware sample rates differ!\n"
            }
        } else {
            report += "- **Graph Format**: ❌ **NIL** (CRITICAL ISSUE)\n"
        }
        
        report += "\n---\n\n## Engine State\n\n"
        
        // Engine status
        report += "- **Engine Running**: \(engine.isRunning ? "✅ Yes" : "❌ No")\n"
        report += "- **Attached Nodes**: \(engine.attachedNodes.count)\n"
        
        // Validate critical nodes
        let criticalNodes: [(String, AVAudioNode)] = [
            ("Output", engine.outputNode),
            ("InputNode", engine.inputNode)
        ]
        
        for (name, node) in criticalNodes {
            let attached = engine.attachedNodes.contains(node)
            report += "- **\(name) Attached**: \(attached ? "✅" : "❌")\n"
        }
        
        report += "\n---\n\n## Health Status\n\n"
        
        // Health monitor status
        let healthResult = healthMonitor.validateState()
        report += "- **Overall Health**: \(healthMonitor.currentHealth)\n"
        report += "- **Validation Issues**: \(healthResult.issues.count)\n\n"
        
        if !healthResult.issues.isEmpty {
            report += "### Issues Found:\n\n"
            for issue in healthResult.issues {
                report += "- \(issue.severity) **\(issue.component)**: \(issue.description)\n"
                if let hint = issue.recoveryHint {
                    report += "  - *Recovery*: \(hint)\n"
                }
            }
            report += "\n"
        }
        
        report += "---\n\n## Error History\n\n"
        
        // Recent errors
        let recentErrors = errorTracker.getRecentErrors(within: 300)  // Last 5 minutes
        report += "- **Recent Errors (5min)**: \(recentErrors.count)\n"
        report += "- **Error Summary**: \(errorTracker.getErrorSummary())\n\n"
        
        if !recentErrors.isEmpty {
            report += "### Recent Errors:\n\n"
            for error in recentErrors.prefix(10) {
                let timeAgo = Int(Date().timeIntervalSince(error.timestamp))
                report += "- **\(timeAgo)s ago** [\(error.severity.displayName)] \(error.component): \(error.message)\n"
            }
            report += "\n"
        }
        
        report += "---\n\n## Performance Metrics\n\n"
        
        // Performance statistics
        report += "- **Summary**: \(performanceMonitor.getSummary())\n\n"
        
        let slowestOps = performanceMonitor.getSlowestOperations(limit: 5)
        if !slowestOps.isEmpty {
            report += "### Slowest Operations:\n\n"
            for (operation, stats) in slowestOps {
                report += "- **\(operation)**: avg=\(String(format: "%.1f", stats.averageDurationMs))ms, "
                report += "max=\(String(format: "%.1f", stats.maxDurationMs))ms, "
                report += "calls=\(stats.callCount), "
                report += "slow=\(String(format: "%.1f", stats.slowPercentage))%\n"
            }
            report += "\n"
        }
        
        report += "---\n\n## Project State\n\n"
        
        if let project = currentProject {
            report += "- **Project Name**: \(project.name)\n"
            report += "- **Tempo**: \(project.tempo) BPM\n"
            report += "- **Time Signature**: \(project.timeSignature.displayString)\n"
            report += "- **Tracks**: \(project.tracks.count)\n"
            report += "- **Buses**: \(project.buses.count)\n"
            report += "- **Duration**: \(String(format: "%.2f", project.durationBeats)) beats\n"
            
            // Track details
            report += "\n### Tracks:\n\n"
            for (index, track) in project.tracks.enumerated() {
                report += "- **Track \(index + 1)**: \(track.name) [\(track.trackType.rawValue)]\n"
                report += "  - Regions: \(track.regions.count) audio, \(track.midiRegions.count) MIDI\n"
                report += "  - Muted: \(track.mixerSettings.isMuted), Solo: \(track.mixerSettings.isSolo)\n"
                report += "  - Volume: \(String(format: "%.2f", track.mixerSettings.volume))\n"
                
                // Check if track node exists
                if let trackNode = trackNodes[track.id] {
                    let hasEngine = trackNode.playerNode.engine != nil
                    let isAttached = engine.attachedNodes.contains(trackNode.playerNode)
                    report += "  - Audio Node: \(hasEngine ? "✅" : "❌") engine, \(isAttached ? "✅" : "❌") attached\n"
                } else {
                    report += "  - Audio Node: ❌ **MISSING**\n"
                }
            }
        } else {
            report += "- **Project**: ❌ No project loaded\n"
        }
        
        report += "\n---\n\n## Audio Graph\n\n"
        
        // Track node status
        report += "- **Track Nodes**: \(trackNodes.count)\n"
        
        for (trackId, trackNode) in trackNodes {
            let trackName = currentProject?.tracks.first(where: { $0.id == trackId })?.name ?? "Unknown"
            let isPlaying = trackNode.playerNode.isPlaying
            let hasConnections = !engine.outputConnectionPoints(for: trackNode.playerNode, outputBus: 0).isEmpty
            
            report += "  - **\(trackName)**: playing=\(isPlaying), connected=\(hasConnections)\n"
        }
        
        // Bus node status
        report += "- **Bus Nodes**: \(busNodes.count)\n"
        
        report += "\n---\n\n## Memory & Resources\n\n"
        
        // Resource pool statistics
        let resourcePool = AudioResourcePool.shared
        report += "- **Memory Allocated**: \(resourcePool.totalMemoryBytes / 1_000_000)MB\n"
        report += "- **Memory Pressure**: \(resourcePool.isUnderMemoryPressure ? "⚠️ Yes" : "✅ No")\n"
        
        let poolStats = resourcePool.getStatistics()
        report += "- **Buffer Allocations**: \(poolStats.totalAllocations)\n"
        report += "- **Buffer Reuses**: \(poolStats.totalReuses)\n"
        report += "- **Reuse Rate**: \(String(format: "%.1f", poolStats.reuseRate * 100))%\n"
        report += "- **Peak Borrowed**: \(poolStats.peakBorrowed)\n"
        report += "- **Rejected Allocations**: \(poolStats.rejectedAllocations)\n"
        
        report += "\n---\n\n## Plugin Delay Compensation\n\n"
        
        let pdcManager = PluginLatencyManager.shared
        report += "- **PDC Enabled**: \(pdcManager.isEnabled ? "✅" : "❌")\n"
        report += "- **Max Latency**: \(String(format: "%.2f", pdcManager.maxLatencyMs))ms (\(pdcManager.maxLatencySamples) samples)\n"
        
        report += "\n---\n\n## Recommendations\n\n"
        
        // Generate recommendations based on health status
        let suggestions = healthMonitor.getRecoverySuggestions()
        if suggestions.isEmpty {
            report += "✅ No issues detected. Engine is healthy.\n"
        } else {
            for suggestion in suggestions {
                report += "- \(suggestion)\n"
            }
        }
        
        report += "\n---\n\n*End of diagnostic report*\n"
        
        return report
    }
    
    /// Save diagnostic report to file.
    /// Returns URL of saved report or nil if failed.
    @discardableResult
    static func saveDiagnosticReport(
        to directory: URL,
        engine: AVAudioEngine,
        graphFormat: AVAudioFormat?,
        trackNodes: [UUID: TrackAudioNode],
        busNodes: [UUID: BusAudioNode],
        currentProject: AudioProject?,
        healthMonitor: AudioEngineHealthMonitor,
        errorTracker: AudioEngineErrorTracker,
        performanceMonitor: AudioPerformanceMonitor
    ) -> URL? {
        let report = generateReport(
            engine: engine,
            graphFormat: graphFormat,
            trackNodes: trackNodes,
            busNodes: busNodes,
            currentProject: currentProject,
            healthMonitor: healthMonitor,
            errorTracker: errorTracker,
            performanceMonitor: performanceMonitor
        )
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "Stori_Diagnostic_\(timestamp).md"
        let fileURL = directory.appendingPathComponent(filename)
        
        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            AppLogger.shared.info("Diagnostic report saved: \(fileURL.path)", category: .audio)
            return fileURL
        } catch {
            AppLogger.shared.error("Failed to save diagnostic report: \(error.localizedDescription)", category: .audio)
            return nil
        }
    }
}
