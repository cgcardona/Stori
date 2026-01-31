//
//  AudioFileReferenceManager.swift
//  Stori
//
//  Manages audio file path resolution and relocation.
//  Converts between absolute URLs and relative paths within project bundles.
//
//  Architecture Note:
//  Audio files can be stored in two locations:
//  1. Project bundle (./Audio/ subfolder) - preferred for portability
//  2. External location (Documents, Downloads, etc.) - stored as absolute path
//
//  When loading a project, this manager resolves relative paths to absolute URLs.
//  When saving, it can optionally copy external files into the project bundle.
//

import Foundation
import AVFoundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Audio File Reference Manager

/// Manages audio file path resolution for project portability.
/// Handles conversion between absolute URLs and relative paths within project bundles.
@MainActor
class AudioFileReferenceManager {
    
    // MARK: - Singleton
    
    static let shared = AudioFileReferenceManager()
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    
    /// Current project directory URL (set when a project is loaded)
    private(set) var currentProjectDirectory: URL?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Project Context
    
    /// Set the current project directory for path resolution
    func setProjectDirectory(_ url: URL) {
        currentProjectDirectory = url
    }
    
    /// Clear the project directory when no project is loaded
    func clearProjectDirectory() {
        currentProjectDirectory = nil
    }
    
    // MARK: - Path Resolution
    
    /// Resolve a stored path to an absolute URL.
    /// Handles both relative paths (within project) and absolute paths (external files).
    /// - Parameters:
    ///   - storedPath: The path as stored in the AudioFile model
    ///   - projectDirectory: The project directory (if different from current)
    /// - Returns: Absolute URL to the audio file, or nil if not found
    /// - Security: Validates paths to prevent directory traversal attacks
    func resolveURL(for storedPath: String, projectDirectory: URL? = nil) -> URL? {
        let projectDir = projectDirectory ?? currentProjectDirectory
        
        // SECURITY: Block path traversal attempts
        if containsPathTraversal(storedPath) {
            return nil
        }
        
        // Check if it's already an absolute path
        if storedPath.hasPrefix("/") || storedPath.hasPrefix("file://") {
            let url = storedPath.hasPrefix("file://")
                ? URL(string: storedPath)
                : URL(fileURLWithPath: storedPath)

            // Verify the file exists at absolute path
            if let url = url, fileManager.fileExists(atPath: url.path) {
                // SECURITY (H-3): Reject symlinks for absolute paths (TOCTOU / escape risk)
                if !isSymbolicLink(at: url) {
                    return url
                }
            }

            // Try to find in project bundle as fallback (file may have been moved)
            if let projectDir = projectDir {
                let filename = (storedPath as NSString).lastPathComponent
                // SECURITY: Validate filename doesn't contain traversal
                guard !containsPathTraversal(filename) else {
                    return nil
                }
                let inProjectPath = projectDir.appendingPathComponent("Audio/\(filename)")
                if fileManager.fileExists(atPath: inProjectPath.path) {
                    return inProjectPath
                }
            }
            
            return url  // Return original URL even if file doesn't exist (for error handling)
        }
        
        // Relative path - resolve against project directory
        guard let projectDir = projectDir else {
            return nil
        }
        
        let resolvedURL = projectDir.appendingPathComponent(storedPath).standardizedFileURL
        
        // SECURITY (M-3): Verify resolved path is strictly within project (use "/" suffix to avoid prefix bypass)
        let projectPath = projectDir.standardizedFileURL.path
        let projectPathWithSlash = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
        guard resolvedURL.path.hasPrefix(projectPathWithSlash) || resolvedURL.path == projectPath else {
            return nil
        }

        // SECURITY (H-3): Reject symbolic links to prevent escape from project directory
        if isSymbolicLink(at: resolvedURL) {
            return nil
        }

        // SECURITY (H-3): Verify canonical path (after resolving symlinks) still within project
        if let canonicalPath = canonicalPath(for: resolvedURL),
           !canonicalPath.hasPrefix(projectPathWithSlash), canonicalPath != projectPath {
            return nil
        }

        if fileManager.fileExists(atPath: resolvedURL.path) {
            return resolvedURL
        }

        // Try common audio subdirectory locations
        let fallbackPaths = [
            projectDir.appendingPathComponent("Audio/\(storedPath)").standardizedFileURL,
            projectDir.appendingPathComponent("Media/\(storedPath)").standardizedFileURL,
        ]

        for fallback in fallbackPaths {
            // SECURITY (M-3): Verify each fallback path is strictly within project
            guard fallback.path.hasPrefix(projectPathWithSlash) || fallback.path == projectPath else { continue }
            // SECURITY (H-3): Reject symlinks in fallback paths
            if isSymbolicLink(at: fallback) { continue }
            if let canonical = canonicalPath(for: fallback),
               !canonical.hasPrefix(projectPathWithSlash), canonical != projectPath { continue }
            if fileManager.fileExists(atPath: fallback.path) {
                return fallback
            }
        }

        return resolvedURL  // Return expected URL for error handling
    }
    
    // MARK: - Security Helpers (H-3)

    /// Returns true if the resource at url is a symbolic link.
    private func isSymbolicLink(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
    }

    /// Resolves the canonical (real) path, resolving any symlinks. Returns nil on failure.
    private func canonicalPath(for url: URL) -> String? {
        url.path.withCString { pathPtr in
            guard let resolved = realpath(pathPtr, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    /// Check if a path contains directory traversal sequences.
    /// M-3: Multiple percent-decode passes to catch triple+ encoding; strict ".." check after decode.
    /// - Parameter path: The path to check
    /// - Returns: True if path contains traversal attempts
    func containsPathTraversal(_ path: String) -> Bool {
        if path.contains("\0") { return true }
        
        // M-3: Decode up to 5 times to catch nested encoding (e.g. %25252e%25252e)
        var testPath = path.precomposedStringWithCanonicalMapping
        for _ in 0..<5 {
            let decoded = testPath.removingPercentEncoding ?? testPath
            if decoded == testPath { break }
            testPath = decoded
        }
        let lower = testPath.lowercased()
        if lower.contains("..") { return true }
        if lower.contains("/..") || lower.contains("\\") || lower.hasPrefix("~") { return true }
        
        // Literal and single/double-encoded patterns
        let traversalPatterns = [
            "..", "%2e%2e", "%252e%252e", "..%2f", "%2f..", "....//", "..\\", "%5c.."
        ]
        let pathLower = path.lowercased()
        for pattern in traversalPatterns {
            if pathLower.contains(pattern) { return true }
        }
        return false
    }
    
    /// Convert an absolute URL to a relative path for storage.
    /// If the file is outside the project bundle, returns the absolute path.
    /// - Parameters:
    ///   - url: The absolute URL to the audio file
    ///   - projectDirectory: The project directory
    ///   - copyToProject: If true, copy external files into the project bundle
    /// - Returns: Path string for storage (relative if within project, absolute otherwise)
    func relativePath(for url: URL, projectDirectory: URL? = nil, copyToProject: Bool = false) -> String {
        let projectDir = projectDirectory ?? currentProjectDirectory
        
        guard let projectDir = projectDir else {
            // No project context - return absolute path
            return url.path
        }
        
        let urlPath = url.standardizedFileURL.path
        let projectPath = projectDir.standardizedFileURL.path
        
        // Check if file is already within project directory
        if urlPath.hasPrefix(projectPath) {
            // Return relative path (strip project directory prefix)
            let relativePath = String(urlPath.dropFirst(projectPath.count))
            return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        }
        
        // File is external
        if copyToProject {
            // Copy file into project bundle
            if let copiedPath = copyFileToProject(url: url, projectDirectory: projectDir) {
                return copiedPath
            }
        }
        
        // Return absolute path for external files
        return url.path
    }
    
    /// Check if a stored path is relative (within project) or absolute (external)
    func isRelativePath(_ storedPath: String) -> Bool {
        return !storedPath.hasPrefix("/") && !storedPath.hasPrefix("file://")
    }
    
    // MARK: - File Operations
    
    /// Copy an external audio file into the project bundle
    /// - Parameters:
    ///   - url: Source URL of the audio file
    ///   - projectDirectory: Destination project directory
    /// - Returns: Relative path within project, or nil if copy failed
    func copyFileToProject(url: URL, projectDirectory: URL) -> String? {
        let audioDir = projectDirectory.appendingPathComponent("Audio")
        
        // Create Audio directory if needed
        do {
            try fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        
        // Generate unique filename to avoid conflicts
        let originalName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var destFilename = "\(originalName).\(ext)"
        var destURL = audioDir.appendingPathComponent(destFilename)
        
        // If file exists, add unique suffix
        var counter = 1
        while fileManager.fileExists(atPath: destURL.path) {
            destFilename = "\(originalName)_\(counter).\(ext)"
            destURL = audioDir.appendingPathComponent(destFilename)
            counter += 1
        }
        
        // Copy the file
        do {
            try fileManager.copyItem(at: url, to: destURL)
            return "Audio/\(destFilename)"
        } catch {
            return nil
        }
    }
    
    /// Collect and copy all external audio files into the project bundle
    /// Use this when "consolidating" a project for transport
    func consolidateProject(project: AudioProject, projectDirectory: URL) -> AudioProject {
        var updatedProject = project
        
        for (trackIndex, track) in project.tracks.enumerated() {
            for (regionIndex, region) in track.regions.enumerated() {
                // Check if this is an external file (absolute path)
                if !region.audioFile.isRelativePath {
                    let url = region.audioFile.url
                    if let relativePath = copyFileToProject(url: url, projectDirectory: projectDirectory) {
                        // Update the audio file with new relative path
                        var updatedAudioFile = region.audioFile
                        updatedAudioFile.storedPath = relativePath
                        
                        var updatedRegion = region
                        updatedRegion.audioFile = updatedAudioFile
                        updatedProject.tracks[trackIndex].regions[regionIndex] = updatedRegion
                    }
                }
            }
        }
        
        return updatedProject
    }
    
    // MARK: - Missing File Detection
    
    /// Find all audio files that are missing (referenced but not found)
    func findMissingFiles(in project: AudioProject, projectDirectory: URL) -> [AudioFile] {
        var missing: [AudioFile] = []
        
        for track in project.tracks {
            for region in track.regions {
                if let url = resolveURL(for: region.audioFile.storedPath, projectDirectory: projectDirectory) {
                    if !fileManager.fileExists(atPath: url.path) {
                        missing.append(region.audioFile)
                    }
                } else {
                    missing.append(region.audioFile)
                }
            }
        }
        
        return missing
    }
    
    /// Attempt to relocate a missing file by searching common locations
    func relocateFile(_ audioFile: AudioFile, projectDirectory: URL) -> URL? {
        let filename = audioFile.name
        let ext = audioFile.format.rawValue
        let fullFilename = "\(filename).\(ext)"
        
        // Search locations
        let searchDirectories: [URL] = [
            projectDirectory.appendingPathComponent("Audio"),
            projectDirectory,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!,
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!,
            FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!,
        ]
        
        for searchDir in searchDirectories {
            let potentialURL = searchDir.appendingPathComponent(fullFilename)
            if fileManager.fileExists(atPath: potentialURL.path) {
                return potentialURL
            }
            
            // Also search subdirectories one level deep
            if let contents = try? fileManager.contentsOfDirectory(at: searchDir, includingPropertiesForKeys: nil) {
                for item in contents where item.hasDirectoryPath {
                    let nestedURL = item.appendingPathComponent(fullFilename)
                    if fileManager.fileExists(atPath: nestedURL.path) {
                        return nestedURL
                    }
                }
            }
        }
        
        return nil
    }
}
