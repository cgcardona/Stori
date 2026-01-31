//
//  MockFileSystem.swift
//  StoriTests
//
//  Mock file system for testing file I/O operations without touching the real file system.
//

import Foundation
@testable import Stori

/// Mock file system for unit testing
/// Simulates file operations in memory without touching the real file system
final class MockFileSystem {
    // MARK: - In-Memory Storage
    
    private var files: [String: Data] = [:]
    private var directories: Set<String> = ["/"]
    
    // MARK: - Call Tracking
    
    var writeFileCallCount = 0
    var readFileCallCount = 0
    var deleteFileCallCount = 0
    var createDirectoryCallCount = 0
    var fileExistsCallCount = 0
    
    var lastWrittenPath: String?
    var lastReadPath: String?
    var lastDeletedPath: String?
    
    // MARK: - Error Simulation
    
    var shouldFailWrite = false
    var shouldFailRead = false
    var shouldFailDelete = false
    var writeError: Error?
    var readError: Error?
    var deleteError: Error?
    
    // MARK: - File Operations
    
    func writeData(_ data: Data, to path: String) throws {
        writeFileCallCount += 1
        lastWrittenPath = path
        
        if shouldFailWrite {
            throw writeError ?? TestError.mockFailure("Write failed")
        }
        
        // Ensure parent directory exists
        let parentPath = (path as NSString).deletingLastPathComponent
        if !parentPath.isEmpty && parentPath != "/" {
            directories.insert(parentPath)
        }
        
        files[path] = data
    }
    
    func readData(from path: String) throws -> Data {
        readFileCallCount += 1
        lastReadPath = path
        
        if shouldFailRead {
            throw readError ?? TestError.mockFailure("Read failed")
        }
        
        guard let data = files[path] else {
            throw TestError.mockFailure("File not found: \(path)")
        }
        
        return data
    }
    
    func deleteFile(at path: String) throws {
        deleteFileCallCount += 1
        lastDeletedPath = path
        
        if shouldFailDelete {
            throw deleteError ?? TestError.mockFailure("Delete failed")
        }
        
        files.removeValue(forKey: path)
    }
    
    func createDirectory(at path: String) throws {
        createDirectoryCallCount += 1
        directories.insert(path)
    }
    
    func fileExists(at path: String) -> Bool {
        fileExistsCallCount += 1
        return files[path] != nil
    }
    
    func directoryExists(at path: String) -> Bool {
        return directories.contains(path)
    }
    
    func contentsOfDirectory(at path: String) throws -> [String] {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return files.keys.filter { $0.hasPrefix(prefix) }.map {
            String($0.dropFirst(prefix.count)).components(separatedBy: "/").first ?? ""
        }
    }
    
    // MARK: - JSON Helpers
    
    func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try writeData(data, to: path)
    }
    
    func readJSON<T: Decodable>(_ type: T.Type, from path: String) throws -> T {
        let data = try readData(from: path)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
    
    // MARK: - Helper Methods
    
    func reset() {
        files.removeAll()
        directories = ["/"]
        
        writeFileCallCount = 0
        readFileCallCount = 0
        deleteFileCallCount = 0
        createDirectoryCallCount = 0
        fileExistsCallCount = 0
        
        lastWrittenPath = nil
        lastReadPath = nil
        lastDeletedPath = nil
        
        shouldFailWrite = false
        shouldFailRead = false
        shouldFailDelete = false
        writeError = nil
        readError = nil
        deleteError = nil
    }
    
    /// Populate with test files
    func populateTestFiles() {
        // Create some test directories
        directories.insert("/tmp")
        directories.insert("/tmp/stori")
        directories.insert("/tmp/stori/projects")
        
        // Create some test files
        files["/tmp/stori/test.txt"] = "Test content".data(using: .utf8)!
    }
    
    /// Get all file paths (for debugging)
    var allFilePaths: [String] {
        Array(files.keys).sorted()
    }
    
    /// Get total stored data size
    var totalDataSize: Int {
        files.values.reduce(0) { $0 + $1.count }
    }
}

// MARK: - URL Extension for Mock

extension MockFileSystem {
    func writeData(_ data: Data, to url: URL) throws {
        try writeData(data, to: url.path)
    }
    
    func readData(from url: URL) throws -> Data {
        try readData(from: url.path)
    }
    
    func deleteFile(at url: URL) throws {
        try deleteFile(at: url.path)
    }
    
    func fileExists(at url: URL) -> Bool {
        fileExists(at: url.path)
    }
}
