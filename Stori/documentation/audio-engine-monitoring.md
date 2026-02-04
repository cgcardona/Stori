# Audio Engine Monitoring and Diagnostics

This document describes the comprehensive monitoring systems that ensure audio engine reliability and help diagnose issues.

## Overview

The audio engine includes four integrated monitoring systems:

1. **Health Monitor** - Validates engine state consistency
2. **Error Tracker** - Tracks and surfaces critical errors
3. **Performance Monitor** - Measures operation timing
4. **Resource Pool** - Manages memory and prevents allocation storms

Together, these systems ensure the DAW maintains professional stability comparable to Logic Pro.

---

## Health Monitoring

### AudioEngineHealthMonitor

Validates that the audio engine's internal state matches the actual AVAudioEngine attachment state.

**Purpose**: Prevent "silent failures" where the UI shows "playing" but audio is broken.

### When to Use

Call `validateState()` before critical operations:
- Starting playback
- Recording
- Inserting plugins
- Changing audio devices

### Usage

```swift
// Quick validation (hot path)
guard audioEngine.healthMonitor.quickValidate() else {
    // Engine not ready - attempt recovery
    return
}

// Full validation (detailed diagnostics)
let result = audioEngine.healthMonitor.validateState()
if !result.isValid {
    for issue in result.criticalIssues {
        print("CRITICAL: \(issue.component) - \(issue.description)")
    }
}
```

### What It Checks

- Engine is running when expected
- Critical nodes (mixer, EQ, limiter) are attached
- Nodes are attached to correct engine instance
- Format consistency across the graph
- Track nodes have valid connections
- State flags match reality

---

## Error Tracking

### AudioEngineErrorTracker

Accumulates errors with severity levels and provides health insights.

**Purpose**: Make audio problems visible instead of silent.

### Error Severity Levels

- **Debug**: Development-only information
- **Info**: Normal operations (e.g., "Project loaded")
- **Warning**: Non-critical issues (e.g., "Format mismatch")
- **Error**: Serious issues (e.g., "Failed to load audio file")
- **Critical**: Immediate attention required (e.g., "Engine won't start")

### Usage

```swift
// Record an error
AudioEngineErrorTracker.shared.recordError(
    severity: .error,
    component: "AudioEngine",
    message: "Failed to schedule audio",
    context: ["trackId": trackId.uuidString]
)

// Check health
switch tracker.engineHealth {
case .healthy:
    print("All good")
case .unhealthy(let reason):
    print("Problem: \(reason)")
case .critical(let reason):
    print("CRITICAL: \(reason)")
    // Trigger emergency recovery
}

// Get error summary for UI
let summary = tracker.getErrorSummary()
// "❌ 3 errors, 5 warnings"
```

### Critical Error Notifications

Critical errors automatically post `Notification.Name.audioEngineCriticalError` for UI alerts.

---

## Performance Monitoring

### AudioPerformanceMonitor

Measures operation timing and identifies performance bottlenecks.

**Purpose**: Find operations that take too long and cause audio dropouts.

### Thresholds

- **Slow**: > 100ms (warning)
- **Very Slow**: > 500ms (error)

### Usage

```swift
// Measure synchronous operation
let result = AudioPerformanceMonitor.shared.measure(operation: "LoadProject") {
    // ... work
    return someValue
}

// Measure async operation
let result = await AudioPerformanceMonitor.shared.measureAsync(operation: "RestorePlugins") {
    await loadPlugins()
    return result
}

// Manual timing
let start = monitor.startTiming()
// ... do work
monitor.recordTiming(operation: "CustomOperation", startTime: start)
```

### Querying Performance

```swift
// Get statistics for an operation
if let stats = monitor.getStatistics(for: "LoadProject") {
    print("Average: \(stats.averageDurationMs)ms")
    print("Max: \(stats.maxDurationMs)ms")
    print("Slow rate: \(stats.slowPercentage)%")
}

// Find slowest operations
let slowest = monitor.getSlowestOperations(limit: 5)
for (operation, stats) in slowest {
    print("\(operation): avg=\(stats.averageDurationMs)ms")
}
```

---

## Resource Pool

### AudioResourcePool

Reuses expensive audio buffers to prevent allocation storms during device changes.

**Purpose**: Prevent memory spikes and beach balls when engine.reset() is called.

### Usage

```swift
// Borrow a buffer
guard let buffer = AudioResourcePool.shared.borrowBuffer(
    format: format,
    frameCapacity: 1024
) else {
    // Under memory pressure - degrade gracefully
    return
}

// Use buffer...

// Return when done
AudioResourcePool.shared.returnBuffer(buffer)
```

### Memory Pressure Handling

```swift
// Handle system memory warning
AudioResourcePool.shared.handleMemoryWarning()

// Check if under pressure
if pool.isUnderMemoryPressure {
    // Skip optional processing
}

// Monitor allocation statistics
let stats = pool.getStatistics()
print("Reuse rate: \(stats.reuseRate * 100)%")
print("Rejected: \(stats.rejectedAllocations)")
```

---

## Comprehensive Diagnostics

### Generating Reports

Use `generateDiagnosticReport()` to create detailed system snapshots:

```swift
// Generate report
let report = audioEngine.generateDiagnosticReport()

// Save to disk
if let url = audioEngine.saveDiagnosticReport() {
    print("Diagnostic saved: \(url.path)")
}
```

### Report Contents

- System information (macOS version, audio hardware)
- Engine state (running, attached nodes, format)
- Health status (validation results, issues)
- Error history (recent errors, severity breakdown)
- Performance metrics (slowest operations, timing stats)
- Project state (tracks, buses, regions)
- Memory & resources (pool statistics, pressure status)
- Plugin delay compensation status
- Recommendations for recovery

### When to Generate

- User reports "audio not working"
- Before filing bug reports
- After crashes or unexpected behavior
- During development to track down issues

---

## Best Practices

### 1. Validate Before Critical Operations

```swift
// Before starting playback
guard healthMonitor.quickValidate() else {
    // Handle error
    return
}

// Before plugin operations
let result = healthMonitor.validateState()
if !result.isValid {
    // Review issues and decide action
}
```

### 2. Track All Failures

Replace silent `continue` or empty `catch {}` blocks:

```swift
// BAD
guard condition else { continue }

// GOOD
guard condition else {
    errorTracker.recordError(
        severity: .warning,
        component: "TrackAudioNode",
        message: "Condition failed - skipping",
        context: ["detail": "..."]
    )
    continue
}
```

### 3. Measure Performance-Critical Paths

```swift
// Measure important operations
await monitor.measureAsync(operation: "ProjectLoad") {
    await loadProject(project)
}
```

### 4. Handle Memory Pressure

```swift
// In your AudioEngine
func handleMemoryWarning() {
    AudioResourcePool.shared.handleMemoryWarning()
    // Clear other caches...
}

// Setup observer (macOS doesn't have automatic warnings)
// Use DISPATCH_SOURCE_TYPE_MEMORYPRESSURE for custom monitoring
```

### 5. Check Health Periodically

```swift
// In long-running sessions
Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
    Task { @MainActor in
        let health = errorTracker.engineHealth
        if health.requiresRecovery {
            // Attempt recovery...
        }
    }
}
```

---

## Integration with Existing Systems

### AudioEngine Integration

The monitoring systems are automatically integrated into AudioEngine:

- `healthMonitor` validates before play/record
- `errorTracker` records all failures
- Performance monitoring wraps graph mutations
- Resource pool manages buffer allocation

### Project Loading

ProjectLifecycleManager uses performance monitoring:

```swift
// Automatic timing of project load phases
// Reports show time spent in each phase
```

### MIDI Scheduler

SampleAccurateMIDIScheduler auto-regenerates stale timing references:

```swift
// Automatic detection and recovery from:
// - Tempo changes
// - Sample rate changes
// - System sleep/wake
```

### Plugin Chain

PluginChain validates state before mutations:

```swift
// Automatic reconciliation if state drifts
if !chain.validateState() {
    chain.reconcileStateWithEngine()
}
```

---

## Troubleshooting Guide

### "Audio not playing"

1. Generate diagnostic report
2. Check health monitor for issues
3. Review recent errors
4. Validate engine state

### "Stuck notes"

1. Check MIDI timing reference staleness
2. Review MIDI block cache
3. Check error tracker for MIDI dispatch failures

### "Slow performance"

1. Review performance monitor statistics
2. Check for high error rates
3. Look for memory pressure indicators
4. Check buffer pool reuse rate

### "Memory issues"

1. Check resource pool statistics
2. Look for rejected allocations
3. Review memory pressure status
4. Clear caches if needed

---

## Performance Impact

All monitoring systems are designed for minimal overhead:

- **Health Monitor**: O(N) for full validation, O(1) for quick check
- **Error Tracker**: Lock-free writes, minimal allocation
- **Performance Monitor**: ~1µs overhead per measurement
- **Resource Pool**: Lock-free acquire/release, O(1) operations

In production, performance monitoring can be disabled if needed:

```swift
AudioPerformanceMonitor.shared.isEnabled = false
```

---

## Future Enhancements

Planned additions:

1. **Auto-Recovery**: Automatic recovery from detected issues
2. **Telemetry Export**: JSON export for analytics
3. **Real-Time Visualization**: Live performance graphs
4. **Smart Alerts**: ML-based anomaly detection
5. **Crash Recovery**: Automatic state restoration

---

*Last Updated: 2026-02-03*
