//
//  DiagnosticLogger.swift
//  Stori
//
//  Writes diagnostic logs to a file for debugging when console isn't working
//

import Foundation

final class DiagnosticLogger {
    static let shared = DiagnosticLogger()
    
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    
    private init() {
        // Write to Desktop for easy access
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        logFileURL = desktop.appendingPathComponent("Stori_Diagnostic_Log.txt")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        // Clear old log on init
        try? FileManager.default.removeItem(at: logFileURL)
    }
    
    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        
        // Also print to console (in case it works)
        print(logLine, terminator: "")
        NSLog("%@", logLine)
        
        // Write to file (guaranteed to work)
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}
