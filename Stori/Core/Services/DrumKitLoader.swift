//
//  DrumKitLoader.swift
//  Stori
//
//  Service for loading and managing drum kit sample packs
//

import Foundation
import AVFoundation

// MARK: - Drum Kit Loader

@MainActor
@Observable
class DrumKitLoader {
    
    // MARK: - Properties
    
    /// All available drum kits
    var availableKits: [DrumKit] = []
    
    /// Currently selected kit (defaults to first available)
    var currentKit: DrumKit = DrumKit.placeholder
    
    /// Loaded audio buffers for current kit
    private var loadedBuffers: [DrumSoundType: AVAudioPCMBuffer] = [:]
    
    /// Standard audio format for samples
    private let audioFormat: AVAudioFormat?
    
    // MARK: - Initialization
    
    init() {
        self.audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)
        loadAvailableKits()
        
        // Set default kit and load samples synchronously to ensure they're ready
        let defaultKit = availableKits.first(where: { $0.name.contains("TR-909") }) ?? availableKits.first
        if let kit = defaultKit {
            currentKit = kit
            loadSamplesForKit(kit)
        }
    }


    /// Load samples for a kit synchronously
    private func loadSamplesForKit(_ kit: DrumKit) {
        // Clear existing buffers
        loadedBuffers.removeAll()
        
        guard kit.directory != nil else {
            #if DEBUG
            print("🔴 [DrumKitLoader] Kit has no directory, cannot load samples")
            #endif
            return
        }
        
        #if DEBUG
        print("🔵 [DrumKitLoader] Loading samples for kit: \(kit.name)")
        print("🔵 [DrumKitLoader] Kit directory: \(kit.directory?.path ?? "nil")")
        print("🔵 [DrumKitLoader] Kit has \(kit.sounds.count) sounds defined in kit.json")
        #endif
        
        var loadedCount = 0
        // Load samples for each sound type
        for soundType in DrumSoundType.allCases {
            if let url = kit.soundURL(for: soundType) {
                #if DEBUG
                print("   Attempting to load \(soundType.rawValue) from \(url.lastPathComponent)")
                #endif
                if let buffer = loadAudioBuffer(from: url) {
                    loadedBuffers[soundType] = buffer
                    loadedCount += 1
                    #if DEBUG
                    print("   ✅ Loaded \(soundType.rawValue) (\(buffer.frameLength) frames)")
                    #endif
                } else {
                    #if DEBUG
                    print("   ❌ Failed to load buffer for \(soundType.rawValue)")
                    #endif
                }
            }
        }
        
        #if DEBUG
        print("✅ [DrumKitLoader] Loaded \(loadedCount)/\(kit.sounds.count) sounds into buffers")
        #endif
    }
    
    // MARK: - Kit Discovery
    
    /// Scan for available drum kits in the app bundle and documents
    func loadAvailableKits() {
        var kits: [DrumKit] = []
        
        #if DEBUG
        print("🔵 [DrumKitLoader] Loading available kits...")
        #endif
        
        // 1. Load from app bundle (Resources/DrumKits/)
        if let bundleKitsURL = Bundle.main.resourceURL?.appendingPathComponent("DrumKits") {
            #if DEBUG
            print("🔵 [DrumKitLoader] Scanning bundle: \(bundleKitsURL.path)")
            #endif
            let bundleKits = loadKitsFromDirectory(bundleKitsURL)
            #if DEBUG
            print("🔵 [DrumKitLoader] Found \(bundleKits.count) kits in bundle")
            #endif
            kits.append(contentsOf: bundleKits)
        }
        
        // 2. Load from Application Support (user-installed kits)
        if let appSupportKitsURL = getAppSupportDrumKitsDirectory() {
            #if DEBUG
            print("🔵 [DrumKitLoader] Scanning Application Support: \(appSupportKitsURL.path)")
            #endif
            let userKits = loadKitsFromDirectory(appSupportKitsURL)
            #if DEBUG
            print("🔵 [DrumKitLoader] Found \(userKits.count) kits in Application Support")
            for kit in userKits {
                print("   - \(kit.name) (dir: \(kit.directory?.lastPathComponent ?? "nil"))")
            }
            #endif
            kits.append(contentsOf: userKits)
        }
        
        #if DEBUG
        print("✅ [DrumKitLoader] Total kits loaded: \(kits.count)")
        #endif
        
        availableKits = kits
    }
    
    /// Load all kits from a directory
    private func loadKitsFromDirectory(_ directory: URL) -> [DrumKit] {
        var kits: [DrumKit] = []
        
        guard FileManager.default.fileExists(atPath: directory.path) else {
            #if DEBUG
            print("🔴 [DrumKitLoader] Directory does not exist: \(directory.path)")
            #endif
            return kits
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            #if DEBUG
            print("🔵 [DrumKitLoader] Found \(contents.count) items in \(directory.lastPathComponent)")
            for item in contents {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
                print("   - \(item.lastPathComponent) (isDir: \(isDir.boolValue))")
            }
            #endif
            
            for itemURL in contents {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    if let kit = loadKit(from: itemURL) {
                        kits.append(kit)
                        #if DEBUG
                        print("✅ [DrumKitLoader] Loaded kit: \(kit.name)")
                        #endif
                    } else {
                        #if DEBUG
                        print("🔴 [DrumKitLoader] Failed to load kit from: \(itemURL.lastPathComponent)")
                        #endif
                    }
                }
            }
        } catch {
            #if DEBUG
            print("🔴 [DrumKitLoader] Error reading directory: \(error)")
            #endif
        }
        
        return kits
    }
    
    /// Load a single kit from a directory
    private func loadKit(from directory: URL) -> DrumKit? {
        let metadataURL = directory.appendingPathComponent("kit.json")
        
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            #if DEBUG
            print("🔴 [DrumKitLoader] No kit.json in \(directory.lastPathComponent)")
            #endif
            return nil
        }
        
        do {
            let data = try Data(contentsOf: metadataURL)
            let metadata = try JSONDecoder().decode(DrumKitMetadata.self, from: data)
            let kit = metadata.toKit(directory: directory)
            return kit
        } catch {
            #if DEBUG
            print("🔴 [DrumKitLoader] Failed to decode kit.json in \(directory.lastPathComponent): \(error)")
            #endif
            return nil
        }
    }
    
    // MARK: - Kit Selection
    
    /// Select a kit and load its samples
    func selectKit(_ kit: DrumKit) async {
        currentKit = kit
        loadSamplesForKit(kit)
    }
    
    // MARK: - Sample Loading
    
    /// SECURITY (H-4): Max single audio file size (100 MB) to prevent memory exhaustion.
    private static let maxAudioFileSize: Int64 = 100_000_000
    
    /// Load an audio file into a buffer with metadata validation (H-4) and header validation (H-1).
    private func loadAudioBuffer(from url: URL) -> AVAudioPCMBuffer? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        // SECURITY (H-4): Check file size before loading
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? Int64,
              fileSize > 0,
              fileSize <= Self.maxAudioFileSize else {
            return nil
        }
        
        // SECURITY (H-1): Validate header before passing to AVAudioFile to reduce decoder/metadata abuse risk
        guard AudioFileHeaderValidator.validateHeader(at: url) else {
            return nil
        }
        
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            
            // SECURITY (H-4): Validate format to prevent decoder abuse
            guard (8000...384_000).contains(format.sampleRate) else {
                return nil
            }
            guard (1...8).contains(format.channelCount) else {
                return nil
            }
            guard audioFile.length > 0, audioFile.length < 100_000_000_000 else {
                return nil
            }
            
            let frameCount = AVAudioFrameCount(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }
            
            try audioFile.read(into: buffer)
            
            // Convert to standard format if needed
            if let standardFormat = audioFormat,
               format != standardFormat {
                return convertBuffer(buffer, to: standardFormat)
            }
            
            return buffer
        } catch {
            return nil
        }
    }
    
    /// Convert a buffer to the standard format
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return buffer // Return original if conversion not possible
        }
        
        let ratio = format.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrameCount) else {
            return buffer
        }
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            return buffer
        }
        
        return outputBuffer
    }
    
    // MARK: - Buffer Access
    
    /// Get the loaded buffer for a sound type
    func buffer(for soundType: DrumSoundType) -> AVAudioPCMBuffer? {
        loadedBuffers[soundType]
    }
    
    /// Check if a specific sound type has a real sample (vs. synthesized fallback)
    func hasSample(for soundType: DrumSoundType) -> Bool {
        loadedBuffers[soundType] != nil
    }
    
    /// Check if we're using samples (vs synthesized)
    var usingSamples: Bool {
        currentKit.directory != nil && !loadedBuffers.isEmpty
    }
    
    // MARK: - Directories
    
    /// Get the Application Support directory for drum kits
    private func getAppSupportDrumKitsDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let drumKitsDir = appSupport
            .appendingPathComponent("Stori")
            .appendingPathComponent("DrumKits")
        
        // Create if doesn't exist
        if !FileManager.default.fileExists(atPath: drumKitsDir.path) {
            try? FileManager.default.createDirectory(at: drumKitsDir, withIntermediateDirectories: true)
        }
        
        return drumKitsDir
    }
    
    /// Get the directory where users can install kits
    var userKitsDirectory: URL? {
        getAppSupportDrumKitsDirectory()
    }
    
    // MARK: - Cleanup
    
    /// Explicit deinit to prevent Swift Concurrency task leak
    /// @Observable + @MainActor classes can have implicit tasks from the Observation framework
    /// that cause memory corruption during deallocation if not properly cleaned up
}

