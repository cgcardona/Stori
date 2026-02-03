//
//  AppLogger.swift
//  Stori
//
//  Centralized logging system for debugging installation and runtime issues.
//  Logs are stored in ~/Library/Logs/Stori/ for easy collection.
//

import Foundation
import os.log
import AppKit

// MARK: - AppLogger

/// Centralized logging for Stori
/// Logs to both Console.app (via OSLog) and text files for easy sharing
final class AppLogger {
    
    // MARK: - Singleton
    
    static let shared = AppLogger()
    
    // MARK: - Log Levels
    
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case critical = "CRITICAL"
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }
    }
    
    enum Category: String {
        case app = "App"
        case setup = "Setup"
        case services = "Services"
        case project = "Project"
        case audio = "Audio"
        case midi = "MIDI"
        case download = "Download"
        case update = "Update"
        case blockchain = "Blockchain"
    }
    
    // MARK: - Properties
    
    private let logsDirectory: URL
    private let mainLogFile: URL
    private let setupLogFile: URL
    private let servicesLogFile: URL
    private var fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.stori.logger", qos: .utility)
    private let osLog = OSLog(subsystem: "com.tellurstori.stori", category: "general")
    
    // MARK: - Initialization
    
    private init() {
        // Use ~/Library/Logs/Stori/ (standard macOS location)
        let libraryLogs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Stori", isDirectory: true)
        
        self.logsDirectory = libraryLogs
        self.mainLogFile = libraryLogs.appendingPathComponent("stori.log")
        self.setupLogFile = libraryLogs.appendingPathComponent("setup.log")
        self.servicesLogFile = libraryLogs.appendingPathComponent("services.log")
        
        createLogsDirectory()
        openMainLogFile()
        writeStartupHeader()
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    // MARK: - Public Logging Methods
    
    func debug(_ message: String, category: Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
    
    func info(_ message: String, category: Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, category: Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }
    
    func error(_ message: String, category: Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
    
    func critical(_ message: String, category: Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .critical, category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Core Logging
    
    private func log(_ message: String, level: Level, category: Category, file: String, function: String, line: Int) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        // Format: [TIMESTAMP] [LEVEL] [Category] Message (File:Line)
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(category.rawValue)] \(message) (\(fileName):\(line))\n"
        
        // Log to OSLog (shows in Console.app)
        os_log("%{public}@", log: osLog, type: level.osLogType, logLine)
        
        // Log to file
        queue.async { [weak self] in
            self?.writeToFile(logLine)
        }
        
        #if DEBUG
        // Also print to Xcode console in debug builds
        #endif
    }
    
    // MARK: - File Operations
    
    private func createLogsDirectory() {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
    
    private func openMainLogFile() {
        // Rotate log if it's too large (> 10MB)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: mainLogFile.path),
           let size = attrs[.size] as? Int64,
           size > 10_000_000 {
            rotateLogFile()
        }
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: mainLogFile.path) {
            FileManager.default.createFile(atPath: mainLogFile.path, contents: nil)
        }
        
        fileHandle = FileHandle(forWritingAtPath: mainLogFile.path)
        fileHandle?.seekToEndOfFile()
    }
    
    private func rotateLogFile() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let rotatedPath = logsDirectory.appendingPathComponent("tellurstori-\(timestamp).log")
        
        try? FileManager.default.moveItem(at: mainLogFile, to: rotatedPath)
    }
    
    private func writeToFile(_ content: String) {
        guard let data = content.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }
    
    private func writeStartupHeader() {
        let separator = String(repeating: "=", count: 80)
        let header = """
        
        \(separator)
        Stori Session Started
        Date: \(Date())
        Version: \(appVersion)
        Build: \(buildNumber)
        macOS: \(macOSVersion)
        Hardware: \(hardwareInfo)
        \(separator)
        
        """
        writeToFile(header)
    }
    
    // MARK: - System Info
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    var hardwareInfo: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    // MARK: - Log Collection
    
    /// Get path to logs directory for sharing
    var logsDirectoryPath: String {
        logsDirectory.path
    }
    
    /// Create a zip of all logs for sharing
    func createDiagnosticsBundle() -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        let zipName = "Stori-Diagnostics-\(timestamp).zip"
        let zipPath = FileManager.default.temporaryDirectory.appendingPathComponent(zipName)
        let srcPath = logsDirectory.path
        let dstPath = zipPath.path
        guard Self.isSafePathForProcess(srcPath), Self.isSafePathForProcess(dstPath) else {
            self.error("Diagnostics bundle path rejected (invalid characters)", category: .app)
            return nil
        }
        // Collect system info
        let systemInfo = collectSystemInfo()
        let systemInfoPath = logsDirectory.appendingPathComponent("system-info.txt")
        try? systemInfo.write(to: systemInfoPath, atomically: true, encoding: .utf8)
        // Create zip using ditto (preserves metadata)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", srcPath, dstPath]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                TempFileManager.track(zipPath)
                return zipPath
            }
        } catch {
            self.error("Failed to create diagnostics bundle: \(error)", category: .app)
        }
        return nil
    }

    /// Rejects paths that could be unsafe when passed to Process (e.g. shell metacharacters).
    private static func isSafePathForProcess(_ path: String) -> Bool {
        let dangerous = CharacterSet(charactersIn: "$`;|&<>(){}")
        return path.unicodeScalars.allSatisfy { !dangerous.contains($0) }
    }
    
    /// Collect detailed system information
    private func collectSystemInfo() -> String {
        var info = """
        ========================================
        Stori System Diagnostics
        Generated: \(Date())
        ========================================
        
        APP INFORMATION
        ---------------
        Version: \(appVersion)
        Build: \(buildNumber)
        Bundle Path: \(Bundle.main.bundlePath)
        
        SYSTEM INFORMATION
        ------------------
        macOS Version: \(macOSVersion)
        Hardware Model: \(hardwareInfo)
        
        """
        
        // Check for installed SoundFonts
        let soundFontsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stori/SoundFonts")
        
        info += """
        
        INSTALLED COMPONENTS
        --------------------
        SoundFonts Directory: \(soundFontsDir.path)
        SoundFonts Exist: \(FileManager.default.fileExists(atPath: soundFontsDir.path) ? "YES" : "NO")
        
        """
        
        // List installed SoundFonts
        if FileManager.default.fileExists(atPath: soundFontsDir.path) {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: soundFontsDir.path) {
                info += "\nInstalled SoundFonts:\n"
                for item in contents {
                    let itemPath = soundFontsDir.appendingPathComponent(item)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: itemPath.path),
                       let size = attrs[.size] as? Int64 {
                        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                        info += "  - \(item) (\(sizeStr))\n"
                    } else {
                        info += "  - \(item)\n"
                    }
                }
            }
        }
        
        // Disk space
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = attrs[.systemFreeSize] as? Int64 {
            let freeSpaceStr = ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)
            info += """
            
            DISK SPACE
            ----------
            Free Space: \(freeSpaceStr)
            
            """
        }
        
        return info
    }
    
    /// Open logs directory in Finder
    func openLogsInFinder() {
        NSWorkspace.shared.open(logsDirectory)
    }
}

// MARK: - Convenience Global Functions

func logDebug(_ message: String, category: AppLogger.Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
}

func logInfo(_ message: String, category: AppLogger.Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
}

func logWarning(_ message: String, category: AppLogger.Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
}

func logError(_ message: String, category: AppLogger.Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
}

func logCritical(_ message: String, category: AppLogger.Category = .app, file: String = #file, function: String = #function, line: Int = #line) {
}
