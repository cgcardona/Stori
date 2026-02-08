//
//  PluginInstance.swift
//  Stori
//
//  Manages the lifecycle of a loaded Audio Unit plugin instance.
//
//  NOTE: @preconcurrency import must be the first import of that module in this file,
//  or the annotation is ignored (Swift compiler limitation; applies to all modules).
@preconcurrency import AVFoundation
@preconcurrency import AudioToolbox
import Foundation
import CoreAudioKit
import Combine
import Observation

// MARK: - Plugin Instance Core (Nonisolated Resource Owner)

/// Owns Audio Unit resources with deterministic RAII cleanup.
///
/// # Architecture: Core + Model Split
///
/// `PluginInstanceCore` is intentionally **not** `@MainActor`. It owns the
/// `AVAudioUnit` / `AUAudioUnit` and cleans them up in `deinit`, which can
/// run on any thread without requiring an actor hop.
///
/// The `@MainActor @Observable` `PluginInstance` holds this core. When the
/// model is released, the core is released, and resources are cleaned up
/// deterministically via RAII — no manual `cleanup()` calls needed.
///
/// This pattern restores proper RAII resource management.
final class PluginInstanceCore {
    
    /// The underlying AUAudioUnit (for advanced access)
    private(set) var auAudioUnit: AUAudioUnit?
    
    /// The AVAudioUnit node (for connecting to AVAudioEngine graph)
    private(set) var avAudioUnit: AVAudioUnit?
    
    /// Cached view controller for the plugin's custom UI
    var cachedViewController: NSViewController?
    
    /// Sample rate used when loading the plugin (for latency calculations and recovery)
    var loadedSampleRate: Double = 48000
    
    /// M-9: Per-instance rate limit using token bucket (no Date allocations).
    var parameterRateLimitLock = os_unfair_lock()
    var parameterTokens: Int = 120
    var lastParameterRefillTime: UInt64 = 0
    
    /// Store the audio unit references
    func setAudioUnit(_ avUnit: AVAudioUnit) {
        self.avAudioUnit = avUnit
        self.auAudioUnit = avUnit.auAudioUnit
    }
    
    /// Explicitly release audio unit resources (for manual cleanup before deinit)
    func clearAudioUnit() {
        cachedViewController = nil
        auAudioUnit?.deallocateRenderResources()
        avAudioUnit = nil
        auAudioUnit = nil
    }
    
    /// RAII: Deterministic cleanup of audio unit resources.
    /// Runs on whatever thread releases the last reference — no actor hop needed.
    deinit {
        if auAudioUnit != nil {
            auAudioUnit?.deallocateRenderResources()
        }
    }
}

// MARK: - Plugin Instance

/// Represents a loaded, running Audio Unit plugin instance
///
/// # Architecture: @MainActor Observable Model
///
/// Owns a `PluginInstanceCore` that manages Audio Unit resource lifetime.
/// UI-facing properties (`isLoaded`, `isBypassed`, `parameters`) are
/// `@Observable` for fine-grained SwiftUI updates.
///
/// When this model is released, the core's `deinit` handles cleanup
/// automatically via RAII.
// PERFORMANCE: Using @Observable for fine-grained SwiftUI updates
@Observable
@MainActor
class PluginInstance: Identifiable {
    
    // MARK: - Observable Properties
    
    @ObservationIgnored
    let id: UUID
    @ObservationIgnored
    let descriptor: PluginDescriptor
    
    var isLoaded: Bool = false
    var isBypassed: Bool = false
    var currentPresetName: String = "Default"
    var parameters: [PluginParameter] = []
    var loadError: String?
    
    // MARK: - Core (Nonisolated Resource Owner)
    
    /// Nonisolated core that owns audio unit resources and handles RAII cleanup.
    @ObservationIgnored
    private let core = PluginInstanceCore()
    
    /// The underlying AUAudioUnit (delegates to core)
    @ObservationIgnored
    var auAudioUnit: AUAudioUnit? { core.auAudioUnit }
    
    /// The AVAudioUnit node (delegates to core)
    @ObservationIgnored
    var avAudioUnit: AVAudioUnit? { core.avAudioUnit }
    
    /// Cached view controller for the plugin's custom UI (delegates to core)
    @ObservationIgnored
    var cachedViewController: NSViewController? {
        get { core.cachedViewController }
        set { core.cachedViewController = newValue }
    }
    
    /// Sample rate used when loading the plugin (delegates to core)
    @ObservationIgnored
    var loadedSampleRate: Double {
        get { core.loadedSampleRate }
        set { core.loadedSampleRate = newValue }
    }
    
    /// M-9: Global rate limiter across all plugin instances (prevents 100 plugins × 120 = 12k/sec).
    private static let globalParameterLimiter = PluginParameterRateLimiter.shared
    
    private static let maxParameterUpdatesPerSecond = 120
    
    // MARK: - Initialization
    
    init(descriptor: PluginDescriptor) {
        self.id = UUID()
        self.descriptor = descriptor
    }
    
    // PluginInstanceCore handles RAII cleanup — no manual deinit needed.
    
    // MARK: - Loading
    
    /// Negotiate the best format for a plugin's buses.
    /// Uses atomic format setting - either both buses are set or neither.
    /// Resets AU state between attempts to clear any partial configuration.
    private func negotiateFormat(for audioUnit: AVAudioUnit, targetRate: Double) throws {
        let au = audioUnit.auAudioUnit
        
        // Deallocate render resources to clear any cached format state
        if au.renderResourcesAllocated {
            au.deallocateRenderResources()
        }
        
        // Reset AU to clear internal format caches
        au.reset()
        
        // Capture plugin's native format before we attempt any changes
        let nativeInputFormat = au.inputBusses[0].format
        let nativeOutputFormat = au.outputBusses[0].format
        let nativeRate = nativeOutputFormat.sampleRate
        
        // Build list of formats to try in priority order
        var formatsToTry: [(format: AVAudioFormat, description: String)] = []
        
        // 1. Preferred: stereo at engine's sample rate
        if let stereoAtTarget = AVAudioFormat(standardFormatWithSampleRate: targetRate, channels: 2) {
            formatsToTry.append((stereoAtTarget, "\(Int(targetRate))Hz stereo"))
        }
        
        // 2. Fallback: stereo at plugin's native rate (if different and valid)
        if nativeRate > 0 && nativeRate != targetRate {
            if let stereoAtNative = AVAudioFormat(standardFormatWithSampleRate: nativeRate, channels: 2) {
                formatsToTry.append((stereoAtNative, "\(Int(nativeRate))Hz stereo (native rate)"))
            }
        }
        
        // 3. Last resort: plugin's exact native formats (may be mono or other channel config)
        // Only try if different from previous attempts
        if nativeInputFormat.channelCount != 2 || nativeOutputFormat.channelCount != 2 {
            // This is handled specially below since input/output may differ
        }
        
        // Try each format with atomic set (both buses or neither)
        for (format, description) in formatsToTry {
            // Reset before each attempt to clear partial state
            au.reset()
            
            do {
                // Set both buses atomically
                try au.inputBusses[0].setFormat(format)
                try au.outputBusses[0].setFormat(format)
                loadedSampleRate = format.sampleRate
                return
            } catch {
                // Reset to clear any partial configuration
                au.reset()
                AppLogger.shared.warning("Plugin '\(descriptor.name)' refused \(description)", category: .audio)
            }
        }
        
        // Last resort: try plugin's exact native formats (may differ between input/output)
        au.reset()
        do {
            try au.inputBusses[0].setFormat(nativeInputFormat)
            try au.outputBusses[0].setFormat(nativeOutputFormat)
            loadedSampleRate = nativeOutputFormat.sampleRate
            AppLogger.shared.warning("Plugin '\(descriptor.name)' using native format: \(Int(nativeOutputFormat.sampleRate))Hz, \(nativeOutputFormat.channelCount)ch", category: .audio)
            return
        } catch {
            au.reset()
            AppLogger.shared.error("Plugin '\(descriptor.name)' format negotiation failed completely", category: .audio)
            throw PluginError.formatNegotiationFailed
        }
    }
    
    /// Instantiate and load the Audio Unit
    /// - Parameter sampleRate: The sample rate to configure the AU buses with (should match engine's hardware rate)
    func load(sampleRate: Double) async throws {
        guard !isLoaded else { return }
        
        loadError = nil
        loadedSampleRate = sampleRate
        
        let componentDesc = descriptor.componentDescription.audioComponentDescription
        
        do {
            // Instantiate the Audio Unit
            let audioUnit = try await AVAudioUnit.instantiate(with: componentDesc, options: [])
            core.setAudioUnit(audioUnit)
            
            // Negotiate format with fallback support
            try negotiateFormat(for: audioUnit, targetRate: sampleRate)
            
            // Load parameters
            loadParameters()
            isLoaded = true
            
        } catch {
            loadError = error.localizedDescription
            throw PluginError.instantiationFailed
        }
    }
    
    /// Instantiate with out-of-process hosting (crash isolation)
    /// - Parameter sampleRate: The sample rate to configure the AU buses with (should match engine's hardware rate)
    func loadSandboxed(sampleRate: Double) async throws {
        guard !isLoaded else { return }
        
        loadError = nil
        loadedSampleRate = sampleRate
        
        let componentDesc = descriptor.componentDescription.audioComponentDescription
        
        do {
            // Use out-of-process instantiation for crash isolation
            let audioUnit = try await AVAudioUnit.instantiate(with: componentDesc, options: .loadOutOfProcess)
            core.setAudioUnit(audioUnit)
            
            // Negotiate format with fallback support
            try negotiateFormat(for: audioUnit, targetRate: sampleRate)
            
            loadParameters()
            isLoaded = true
        } catch {
            loadError = error.localizedDescription
            throw PluginError.instantiationFailed
        }
    }

    /// Unload and release resources (explicit cleanup — also handled by core's RAII deinit)
    func unload() {
        guard isLoaded else { return }
        
        core.clearAudioUnit()
        parameters.removeAll()
        isLoaded = false
    }
    
    // MARK: - Parameters
    
    private func loadParameters() {
        guard let au = auAudioUnit, let tree = au.parameterTree else {
            parameters = []
            return
        }
        
        parameters = tree.allParameters.map { param in
            PluginParameter(
                address: param.address,
                name: param.displayName,
                value: param.value,
                minValue: param.minValue,
                maxValue: param.maxValue,
                unit: param.unitName ?? "",
                flags: param.flags
            )
        }
    }
    
    /// Set a parameter value. Rate-limited (per-plugin and global) to avoid DoS (M-9).
    /// Uses token bucket algorithm for O(1) performance with no allocations.
    func setParameter(address: AUParameterAddress, value: AUValue) {
        // Global rate limit first
        guard Self.globalParameterLimiter.shouldAllow() else { return }
        
        // Per-instance rate limit using token bucket
        os_unfair_lock_lock(&core.parameterRateLimitLock)
        
        let now = mach_absolute_time()
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        
        // Refill tokens based on elapsed time (1 token per 8.33ms at 120/sec)
        let elapsedNanos = (now - core.lastParameterRefillTime) * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        let refillIntervalNanos: UInt64 = 1_000_000_000 / UInt64(Self.maxParameterUpdatesPerSecond)
        let tokensToAdd = Int(elapsedNanos / refillIntervalNanos)
        
        if tokensToAdd > 0 {
            core.parameterTokens = min(Self.maxParameterUpdatesPerSecond, core.parameterTokens + tokensToAdd)
            core.lastParameterRefillTime = now
        }
        
        // Try to consume a token
        guard core.parameterTokens > 0 else {
            os_unfair_lock_unlock(&core.parameterRateLimitLock)
            return
        }
        core.parameterTokens -= 1
        os_unfair_lock_unlock(&core.parameterRateLimitLock)
        
        guard let tree = auAudioUnit?.parameterTree,
              let param = tree.parameter(withAddress: address) else {
            return
        }
        param.setValue(value, originator: nil)
        if let idx = parameters.firstIndex(where: { $0.address == address }) {
            parameters[idx].value = value
        }
    }
    
    /// Get current value of a parameter
    func getParameter(address: AUParameterAddress) -> AUValue? {
        auAudioUnit?.parameterTree?.parameter(withAddress: address)?.value
    }
    
    // MARK: - UI
    
    /// Request the plugin's custom UI view controller (if available)
    func requestViewController() async -> NSViewController? {
        guard isLoaded, let au = auAudioUnit else {
            return nil
        }
        
        // Return cached view controller if available
        // Audio Units typically only create one view controller instance
        if let cached = cachedViewController {
            return cached
        }
        
        let vc = await withCheckedContinuation { continuation in
            au.requestViewController { viewController in
                continuation.resume(returning: viewController)
            }
        }
        
        // Cache the view controller for future use
        cachedViewController = vc
        return vc
    }
    
    // MARK: - Presets
    
    /// Get factory presets provided by the plugin
    func getFactoryPresets() -> [AUAudioUnitPreset] {
        auAudioUnit?.factoryPresets ?? []
    }
    
    /// Select a factory preset
    func selectPreset(_ preset: AUAudioUnitPreset) {
        auAudioUnit?.currentPreset = preset
        currentPresetName = preset.name
        
        // Reload parameters after preset change
        loadParameters()
    }
    
    /// Get current preset (if any)
    func getCurrentPreset() -> AUAudioUnitPreset? {
        auAudioUnit?.currentPreset
    }
    
    /// Save the current state as user preset data
    func saveState() throws -> Data {
        guard let fullState = auAudioUnit?.fullState else {
            throw PluginError.stateNotAvailable
        }
        return try PropertyListSerialization.data(fromPropertyList: fullState, format: .binary, options: 0)
    }
    
    /// Maximum plugin state size (10 MB) to prevent memory exhaustion from malicious presets.
    private static let maxPluginStateSize = 10_000_000
    
    /// Maximum nesting depth for plugin state (H-2: prevent DoS from deeply nested plists).
    private static let maxPluginStateDepth = 10

    /// Timeout for plugin state restoration (protects against hung plugins)
    private static let stateRestoreTimeout: TimeInterval = 5.0
    
    /// Restore state from saved data with validation, timeout, and graceful fallback (async version)
    /// Returns true if state was restored successfully, false if falling back to defaults
    /// SECURITY (H-2): Validates structure and value types before passing to plugin.
    /// PERFORMANCE: Async - does not block the calling thread
    @discardableResult
    func restoreState(from data: Data) async -> Bool {
        // Validate size
        guard data.count <= Self.maxPluginStateSize else {
            AppLogger.shared.warning("Plugin state exceeds max size", category: .audio)
            loadParameters()
            return false
        }
        
        // Parse plist synchronously — PropertyListSerialization is fast and thread-safe
        let fullState: [String: Any]
        do {
            guard let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                loadParameters()
                return false
            }
            fullState = parsed
        } catch {
            loadParameters()
            return false
        }
        
        guard !fullState.isEmpty else {
            loadParameters()
            return false
        }
        
        // Validate structure
        guard validatePluginState(fullState) else {
            AppLogger.shared.warning("Invalid plugin state structure rejected", category: .audio)
            loadParameters()
            return false
        }
        
        // Validate the plugin is ready to receive state
        guard let auUnit = auAudioUnit else {
            loadParameters()
            return false
        }
        
        // Apply state synchronously — AUAudioUnit.fullState= is a synchronous setter.
        // Wrapped in a timeout task to protect against hung plugins.
        let applied: Bool
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    auUnit.fullState = fullState
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(Self.stateRestoreTimeout * 1_000_000_000))
                    throw CancellationError()
                }
                // Wait for whichever finishes first
                try await group.next()
                group.cancelAll()
            }
            applied = true
        } catch {
            applied = false
        }
        
        if !applied {
            AppLogger.shared.warning("Plugin state restoration timed out for '\(descriptor.name)'", category: .audio)
            loadParameters()
            return false
        }
        
        // Verify state was accepted
        guard auUnit.parameterTree != nil else {
            AppLogger.shared.warning("Plugin rejected state (parameter tree nil), using defaults", category: .audio)
            loadParameters()
            return false
        }
        
        loadParameters()
        return true
    }
    
    /// Synchronous restore for compatibility (calls async version)
    /// Prefer the async version when possible
    @discardableResult
    func restoreStateSync(from data: Data) -> Bool {
        // For callers that can't use async, run on background and wait
        // This is less ideal but maintains compatibility
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        
        Task { @MainActor [weak self] in
            if let self {
                result = await self.restoreState(from: data)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
    
    // MARK: - Plugin State Validation (H-2)
    
    /// Validates plugin state structure before passing to AU (depth, size, value types).
    private func validatePluginState(_ state: [String: Any]) -> Bool {
        guard validateDictionaryDepth(state, maxDepth: Self.maxPluginStateDepth, currentDepth: 0) else {
            return false
        }
        guard let serialized = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0),
              serialized.count <= Self.maxPluginStateSize else {
            return false
        }
        for (_, value) in state {
            guard validateValueType(value) else { return false }
        }
        return true
    }
    
    private func validateDictionaryDepth(_ obj: Any, maxDepth: Int, currentDepth: Int) -> Bool {
        guard currentDepth <= maxDepth else { return false }
        if let dict = obj as? [String: Any] {
            for value in dict.values {
                if !validateDictionaryDepth(value, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                    return false
                }
            }
        } else if let array = obj as? [Any] {
            for item in array {
                if !validateDictionaryDepth(item, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                    return false
                }
            }
        }
        return true
    }
    
    private func validateValueType(_ value: Any) -> Bool {
        switch value {
        case is String, is Int, is Double, is Float, is Bool, is Data, is Date:
            return true
        case is NSNumber:  // Plist can decode numbers as NSNumber
            return true
        case let array as [Any]:
            return array.allSatisfy { validateValueType($0) }
        case let dict as [String: Any]:
            return dict.values.allSatisfy { validateValueType($0) }
        default:
            return false
        }
    }
    
    /// Create a PluginConfiguration for project persistence (async version)
    ///
    /// PERFORMANCE: Offloads PropertyListSerialization to a background thread to avoid
    /// blocking the main thread during project save, especially when many plugins are loaded.
    func createConfigurationAsync(atSlot slotIndex: Int) async -> PluginConfiguration {
        let fullState = auAudioUnit?.fullState
        let currentDescriptor = descriptor
        let currentBypassed = isBypassed
        
        // Offload serialization to background thread
        let stateData: Data? = await Task.detached(priority: .userInitiated) {
            guard let fullState = fullState else { return nil }
            return try? PropertyListSerialization.data(fromPropertyList: fullState, format: .binary, options: 0)
        }.value
        
        return PluginConfiguration(
            slotIndex: slotIndex,
            descriptor: currentDescriptor,
            isBypassed: currentBypassed,
            fullState: stateData
        )
    }
    
    /// Create a PluginConfiguration for project persistence (synchronous version)
    /// NOTE: For non-blocking save operations, prefer `createConfigurationAsync` instead.
    func createConfiguration(atSlot slotIndex: Int) -> PluginConfiguration {
        var stateData: Data? = nil
        if let fullState = auAudioUnit?.fullState {
            stateData = try? PropertyListSerialization.data(fromPropertyList: fullState, format: .binary, options: 0)
        }
        
        return PluginConfiguration(
            slotIndex: slotIndex,
            descriptor: descriptor,
            isBypassed: isBypassed,
            fullState: stateData
        )
    }
    
    // MARK: - Bypass
    
    /// Toggle bypass state
    func toggleBypass() {
        isBypassed.toggle()
        auAudioUnit?.shouldBypassEffect = isBypassed
    }
    
    /// Set bypass state explicitly
    func setBypass(_ bypassed: Bool) {
        
        isBypassed = bypassed
        auAudioUnit?.shouldBypassEffect = bypassed
        
    }
    
    // MARK: - Offline Render Cloning
    
    /// Clone this plugin for offline rendering
    /// Creates a fresh AU instance with the same component and state for use in export
    /// - Returns: A new AVAudioUnit configured with identical settings
    /// - Throws: PluginError if cloning fails
    nonisolated func cloneForOfflineRender() async throws -> AVAudioUnit {
        // Capture descriptor and state on MainActor
        let componentDesc = await descriptor.componentDescription.audioComponentDescription
        let currentState: [String: Any]? = await auAudioUnit?.fullState
        let currentBypass = await isBypassed
        
        // Instantiate fresh AU with same component description
        let clone: AVAudioUnit
        do {
            clone = try await AVAudioUnit.instantiate(with: componentDesc, options: [])
        } catch {
            throw PluginError.instantiationFailed
        }
        
        // Copy state from live plugin to clone
        if let state = currentState {
            clone.auAudioUnit.fullState = state
        } else {
        }
        
        // Copy bypass state
        clone.auAudioUnit.shouldBypassEffect = currentBypass
        
        return clone
    }
    
    // MARK: - Latency
    
    /// Get the plugin's processing latency in seconds
    var latency: TimeInterval {
        auAudioUnit?.latency ?? 0
    }
    
    /// Get the plugin's processing latency in samples (at the loaded sample rate)
    var latencySamples: Int {
        Int(latency * loadedSampleRate)
    }
    
    // MARK: - Tail Time
    
    /// Get the plugin's tail time (for reverbs, delays, etc.)
    var tailTime: TimeInterval {
        auAudioUnit?.tailTime ?? 0
    }
    
    // MARK: - Sidechain Support
    
    /// Whether this plugin supports sidechain input (has more than 1 input bus)
    ///
    /// NOTE: Apple's built-in plugins (AUDynamicsProcessor, etc.) do NOT expose sidechain buses
    /// through the public Audio Unit v3 API, even though some support sidechain in other DAWs.
    /// Third-party plugins like FabFilter Pro-C 2, Waves C1, etc. properly expose sidechain buses.
    var supportsSidechain: Bool {
        guard let au = auAudioUnit else { return false }
        return au.inputBusses.count > 1
    }
    
    /// Number of input buses (1 = no sidechain, 2+ = has sidechain)
    var inputBusCount: Int {
        auAudioUnit?.inputBusses.count ?? 0
    }
    
    /// Get the sidechain input bus (bus index 1)
    var sidechainBus: AUAudioUnitBus? {
        guard let au = auAudioUnit, au.inputBusses.count > 1 else { return nil }
        return au.inputBusses[1]
    }
    
    /// Get the format expected by the sidechain bus
    var sidechainFormat: AVAudioFormat? {
        sidechainBus?.format
    }
}

// MARK: - Global Plugin Parameter Rate Limiter (M-9)

/// M-9: Global rate limiter for plugin parameter updates across all instances.
/// Uses token bucket algorithm with mach_absolute_time() for high-performance rate limiting.
/// Prevents DoS when many plugins receive updates simultaneously (e.g. automation).
///
/// LOGGING: Logs a warning when rate limiting kicks in, throttled to at most once per second.
///
/// ARCHITECTURE: Nonisolated + @unchecked Sendable with internal lock.
/// Not @MainActor — parameter updates can come from automation threads.
final class PluginParameterRateLimiter: @unchecked Sendable {
    static let shared = PluginParameterRateLimiter()
    
    private var lock = os_unfair_lock()
    private let maxTokens: Int = 1000  // Max updates per second
    private var tokens: Int = 1000
    private var lastRefillTime: UInt64 = 0
    private let refillIntervalNanos: UInt64  // Nanoseconds per token refill
    
    /// Tracking for throttled warning log
    private var droppedUpdateCount: Int = 0
    private var lastWarningTime: UInt64 = 0
    private let warningIntervalNanos: UInt64 = 1_000_000_000  // 1 second
    
    /// Cached timebase info (expensive to compute)
    private let timebaseInfo: mach_timebase_info_data_t
    
    private init() {
        // Calculate nanoseconds per token based on max rate
        // 1 second = 1_000_000_000 nanoseconds
        refillIntervalNanos = 1_000_000_000 / UInt64(maxTokens)
        lastRefillTime = mach_absolute_time()
        
        // Cache timebase info
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebaseInfo = info
    }
    
    // os_unfair_lock is a value type cleaned up by ARC — no manual deinit needed.
    
    /// Returns true if the update is allowed; false if global limit exceeded.
    /// Uses token bucket algorithm: O(1) time complexity, no allocations.
    /// Logs a throttled warning when updates are dropped.
    func shouldAllow() -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let now = mach_absolute_time()
        
        // Convert mach time to nanoseconds using cached timebase
        let elapsedNanos = (now - lastRefillTime) * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        
        // Refill tokens based on elapsed time
        let tokensToAdd = Int(elapsedNanos / refillIntervalNanos)
        if tokensToAdd > 0 {
            tokens = min(maxTokens, tokens + tokensToAdd)
            lastRefillTime = now
        }
        
        // Try to consume a token
        if tokens > 0 {
            tokens -= 1
            return true
        }
        
        // Rate limit exceeded - track and potentially log
        droppedUpdateCount += 1
        
        // Throttled logging: warn at most once per second
        let timeSinceWarning = (now - lastWarningTime) * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        if timeSinceWarning >= warningIntervalNanos {
            let count = droppedUpdateCount
            lastWarningTime = now
            droppedUpdateCount = 0
            
            // Log outside the lock to avoid blocking
            // Use async to avoid blocking the caller (which may be on a high-priority queue)
            DispatchQueue.global(qos: .utility).async {
                AppLogger.shared.warning(
                    "Plugin parameter rate limit exceeded: dropped \(count) updates in the last second",
                    category: .audio
                )
            }
        }
        
        return false
    }
    
    /// Get statistics for debugging (thread-safe)
    var statistics: (currentTokens: Int, droppedSinceLastWarning: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (tokens, droppedUpdateCount)
    }
}

// MARK: - Plugin Instance Manager Protocol

/// Protocol for PluginInstanceManager to enable dependency injection and testing
@MainActor
protocol PluginInstanceManagerProtocol: AnyObject {
    func createInstance(from descriptor: PluginDescriptor) -> PluginInstance
    func removeInstance(_ instance: PluginInstance)
    func removeInstance(withId id: UUID)
    func instance(withId id: UUID) -> PluginInstance?
}

// MARK: - Plugin Instance Manager

/// Manages all active plugin instances across the project.
///
/// ARCHITECTURE: @MainActor @Observable for UI state.
/// Resource cleanup is handled by PluginInstanceCore RAII — when instances
/// are removed from the dictionary, their cores release AU resources automatically.
@Observable
@MainActor
class PluginInstanceManager: PluginInstanceManagerProtocol {
    /// Shared instance for production use
    /// Use dependency injection for testing by passing instances directly
    @ObservationIgnored
    static let shared = PluginInstanceManager()
    
    /// Public initializer enables creating instances for testing
    init() {}
    
    /// All active plugin instances keyed by their ID
    var instances: [UUID: PluginInstance] = [:]
    
    /// Create a new plugin instance
    func createInstance(from descriptor: PluginDescriptor) -> PluginInstance {
        let instance = PluginInstance(descriptor: descriptor)
        instances[instance.id] = instance
        return instance
    }
    
    /// Remove and unload a plugin instance
    func removeInstance(_ instance: PluginInstance) {
        instance.unload()
        instances.removeValue(forKey: instance.id)
    }
    
    /// Remove and unload a plugin instance by ID
    func removeInstance(withId id: UUID) {
        if let instance = instances[id] {
            instance.unload()
            instances.removeValue(forKey: id)
        }
    }
    
    /// Get an instance by ID
    func instance(withId id: UUID) -> PluginInstance? {
        instances[id]
    }
    
    /// Unload all instances (for cleanup)
    func unloadAll() {
        for instance in instances.values {
            instance.unload()
        }
        instances.removeAll()
    }
    
}
