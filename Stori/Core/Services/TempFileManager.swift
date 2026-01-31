//
//  TempFileManager.swift
//  Stori
//
//  M-2: Tracks temp file URLs and removes them on app terminate to avoid leaving garbage.
//

import Foundation

/// Tracks temporary file URLs and deletes them on app termination.
enum TempFileManager {
    private static let lock = NSLock()
    private static var _tracked: Set<URL> = []
    private static var tracked: Set<URL> {
        get { lock.lock(); defer { lock.unlock() }; return _tracked }
        set { lock.lock(); defer { lock.unlock() }; _tracked = newValue }
    }

    /// Call when creating a temp file so it can be cleaned up on terminate.
    static func track(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        _tracked.insert(url)
    }

    /// Remove from tracking (e.g. after moving to final destination). Optionally delete now.
    static func untrack(_ url: URL, deleteIfExists: Bool = false) {
        lock.lock()
        _tracked.remove(url)
        lock.unlock()
        if deleteIfExists, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Delete all currently tracked temp files. Call from applicationWillTerminate.
    static func cleanupAll() {
        lock.lock()
        let urls = _tracked
        _tracked.removeAll()
        lock.unlock()
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
