//
//  AssetDownloadService.swift
//  Stori
//
//  On-demand download of drum kits and GM SoundFont from backend (presigned S3 URLs).
//

import Foundation

// MARK: - Asset Download Service

@MainActor
@Observable
final class AssetDownloadService {

    static let shared = AssetDownloadService()

    private let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder

    /// Progress 0...1 for current download (nil when idle)
    private(set) var downloadProgress: Double?

    /// Last error message for UI
    private(set) var lastError: String?

    init(baseURL: String = AppConfig.apiBaseURL) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Paths

    private static var storiApplicationSupport: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Stori")
    }

    private static var drumKitsDirectory: URL? {
        storiApplicationSupport?.appendingPathComponent("DrumKits")
    }

    private static var soundFontsDirectory: URL? {
        storiApplicationSupport?.appendingPathComponent("SoundFonts")
    }

    // MARK: - List API

    /// GET /api/v1/assets/drum-kits
    func listDrumKits() async throws -> [DrumKitItem] {
        lastError = nil
        guard let url = URL(string: "\(baseURL)/api/v1/assets/drum-kits") else {
            throw AssetDownloadError.invalidURL
        }
        #if DEBUG
        print("🔵 [AssetDownload] Fetching drum kit list from: \(url.absoluteString)")
        #endif
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = AppConfig.defaultTimeout
        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data)
            let kits: [DrumKitItem]
            do {
                kits = try decoder.decode([DrumKitItem].self, from: data)
            } catch {
                #if DEBUG
                print("🔴 [AssetDownload] Failed to decode drum kit list: \(error)")
                if let bodyString = String(data: data, encoding: .utf8) {
                    print("🔴 [AssetDownload] Response body: \(bodyString)")
                }
                #endif
                lastError = "Invalid response from server. Please try again."
                throw AssetDownloadError.network(error)
            }
            #if DEBUG
            print("✅ [AssetDownload] Got \(kits.count) drum kits:")
            for kit in kits {
                print("   - id: '\(kit.id)', name: '\(kit.name)', version: '\(kit.version)'")
            }
            #endif
            return kits
        } catch {
            if lastError == nil { lastError = userFriendlyErrorMessage(for: error) }
            throw error
        }
    }

    /// GET /api/v1/assets/soundfonts
    func listSoundfonts() async throws -> [SoundFontItem] {
        lastError = nil
        guard let url = URL(string: "\(baseURL)/api/v1/assets/soundfonts") else {
            throw AssetDownloadError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = AppConfig.defaultTimeout
        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data)
            let soundfonts: [SoundFontItem]
            do {
                soundfonts = try decoder.decode([SoundFontItem].self, from: data)
            } catch {
                #if DEBUG
                print("🔴 [AssetDownload] Failed to decode soundfont list: \(error)")
                #endif
                lastError = "Invalid response from server. Please try again."
                throw AssetDownloadError.network(error)
            }
            return soundfonts
        } catch {
            if lastError == nil { lastError = userFriendlyErrorMessage(for: error) }
            throw error
        }
    }

    // MARK: - Download URL API

    /// GET /api/v1/assets/drum-kits/{kit_id}/download-url
    func getDrumKitDownloadURL(kitId: String, expiresIn: Int = 3600) async throws -> DownloadURLResponse {
        lastError = nil
        guard let url = URL(string: "\(baseURL)/api/v1/assets/drum-kits/\(kitId)/download-url?expires_in=\(expiresIn)") else {
            throw AssetDownloadError.invalidURL
        }
        #if DEBUG
        print("🔵 [AssetDownload] Requesting download URL for kit: '\(kitId)'")
        print("🔵 [AssetDownload] URL: \(url.absoluteString)")
        #endif
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = AppConfig.defaultTimeout
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                #if DEBUG
                print("🔵 [AssetDownload] Response: HTTP \(http.statusCode) for kit '\(kitId)'")
                if http.statusCode == 404 {
                    // Log response body for debugging
                    if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                        print("🔴 [AssetDownload] 404 Response body: \(body)")
                    }
                    print("🔴 [AssetDownload] Kit '\(kitId)' not found. Available kits from list API:")
                    do {
                        let availableKits = try await listDrumKits()
                        print("🔴 [AssetDownload] List API returned \(availableKits.count) kits:")
                        for kit in availableKits {
                            print("   - id: '\(kit.id)', name: '\(kit.name)'")
                        }
                        // Check if kitId matches any (case-sensitive)
                        let matches = availableKits.filter { $0.id == kitId }
                        if matches.isEmpty {
                            print("🔴 [AssetDownload] ⚠️ Kit ID '\(kitId)' does NOT match any kit from list API!")
                            print("🔴 [AssetDownload] Trying case-insensitive match...")
                            let caseInsensitiveMatches = availableKits.filter { $0.id.lowercased() == kitId.lowercased() }
                            if !caseInsensitiveMatches.isEmpty {
                                print("🔴 [AssetDownload] Found case-insensitive match: '\(caseInsensitiveMatches[0].id)' (you used '\(kitId)')")
                            }
                        } else {
                            print("🔴 [AssetDownload] ✅ Kit ID '\(kitId)' EXISTS in list API but download-url returns 404!")
                            print("🔴 [AssetDownload] This suggests a backend bug: list and download-url endpoints disagree.")
                        }
                    } catch {
                        print("   (Could not fetch kit list: \(error.localizedDescription))")
                    }
                }
                #endif
            }
            try validateResponse(response, data: data)
            #if DEBUG
            if let bodyString = String(data: data, encoding: .utf8) {
                print("🔵 [AssetDownload] Response body: \(bodyString)")
            }
            #endif
            let result: DownloadURLResponse
            do {
                result = try decoder.decode(DownloadURLResponse.self, from: data)
            } catch {
                #if DEBUG
                print("🔴 [AssetDownload] Failed to decode DownloadURLResponse for kit '\(kitId)': \(error)")
                if let bodyString = String(data: data, encoding: .utf8) {
                    print("🔴 [AssetDownload] Response body was: \(bodyString)")
                }
                #endif
                lastError = "Invalid response from server. Please try again."
                throw AssetDownloadError.network(error)
            }
            #if DEBUG
            print("✅ [AssetDownload] Got download URL for kit '\(kitId)': \(result.url.prefix(50))...")
            #endif
            return result
        } catch {
            if lastError == nil {
                // For 404, use a user-friendly message without server URL
                if case AssetDownloadError.notFound = error {
                    lastError = "This pack is not available."
                } else {
                    // Don't expose server URL in user-facing errors
                    lastError = userFriendlyErrorMessage(for: error)
                }
            }
            throw error
        }
    }

    /// GET /api/v1/assets/soundfonts/{soundfont_id}/download-url
    func getSoundFontDownloadURL(soundfontId: String, expiresIn: Int = 3600) async throws -> DownloadURLResponse {
        lastError = nil
        guard let url = URL(string: "\(baseURL)/api/v1/assets/soundfonts/\(soundfontId)/download-url?expires_in=\(expiresIn)") else {
            throw AssetDownloadError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = AppConfig.defaultTimeout
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(DownloadURLResponse.self, from: data)
    }

    /// GET /api/v1/assets/bundle/download-url (optional)
    func getBundleDownloadURL(expiresIn: Int = 3600) async throws -> DownloadURLResponse {
        lastError = nil
        guard let url = URL(string: "\(baseURL)/api/v1/assets/bundle/download-url?expires_in=\(expiresIn)") else {
            throw AssetDownloadError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = AppConfig.defaultTimeout
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(DownloadURLResponse.self, from: data)
    }

    // MARK: - Download + Install

    /// Download drum kit zip and unzip to Application Support/Stori/DrumKits/{kitId}/
    func downloadDrumKit(kitId: String, progress: ((Double) -> Void)? = nil) async throws {
        downloadProgress = 0
        defer { downloadProgress = nil }
        lastError = nil

        let downloadURLResponse: DownloadURLResponse
        do {
            downloadURLResponse = try await getDrumKitDownloadURL(kitId: kitId)
        } catch {
            // Error already logged and lastError set in getDrumKitDownloadURL
            throw error
        }
        
        guard let presignedURL = URL(string: downloadURLResponse.url) else {
            lastError = "Invalid download URL."
            throw AssetDownloadError.invalidURL
        }

        #if DEBUG
        print("🔵 [AssetDownload] Downloading kit '\(kitId)' from presigned URL: \(presignedURL.absoluteString.prefix(80))...")
        #endif

        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("stori_kit_\(kitId).zip")
        defer { try? FileManager.default.removeItem(at: tempZip) }

        do {
            try await downloadToFile(url: presignedURL, destination: tempZip, progress: progress)
        } catch {
            #if DEBUG
            print("🔴 [AssetDownload] Failed to download kit '\(kitId)' from presigned URL: \(error)")
            #endif
            lastError = "Download failed. Please check your connection and try again."
            throw error
        }

        guard let kitsDir = Self.drumKitsDirectory else {
            throw AssetDownloadError.fileWriteFailed
        }
        try FileManager.default.createDirectory(at: kitsDir, withIntermediateDirectories: true)
        let kitDir = kitsDir.appendingPathComponent(kitId)
        try FileManager.default.createDirectory(at: kitDir, withIntermediateDirectories: true)

        try unzipKit(zipURL: tempZip, toKitDir: kitDir, kitId: kitId)
    }

    /// Download SoundFont and save to Application Support/Stori/SoundFonts/{filename}
    func downloadSoundFont(soundfontId: String, filename: String, progress: ((Double) -> Void)? = nil) async throws {
        downloadProgress = 0
        defer { downloadProgress = nil }
        lastError = nil

        let downloadURLResponse = try await getSoundFontDownloadURL(soundfontId: soundfontId)
        guard let presignedURL = URL(string: downloadURLResponse.url) else {
            throw AssetDownloadError.invalidURL
        }

        guard let soundFontsDir = Self.soundFontsDirectory else {
            throw AssetDownloadError.fileWriteFailed
        }
        try FileManager.default.createDirectory(at: soundFontsDir, withIntermediateDirectories: true)
        let destFile = soundFontsDir.appendingPathComponent(filename)

        try await downloadToFile(url: presignedURL, destination: destFile, progress: progress)
    }

    /// Download bundle zip and extract drum-kits + soundfonts to Application Support
    func downloadBundle(progress: ((Double) -> Void)? = nil) async throws {
        downloadProgress = 0
        defer { downloadProgress = nil }
        lastError = nil

        let downloadURLResponse = try await getBundleDownloadURL()
        guard let presignedURL = URL(string: downloadURLResponse.url) else {
            throw AssetDownloadError.invalidURL
        }

        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("stori_assets_bundle.zip")
        defer { try? FileManager.default.removeItem(at: tempZip) }

        try await downloadToFile(url: presignedURL, destination: tempZip, progress: progress)

        let tempExtract = FileManager.default.temporaryDirectory
            .appendingPathComponent("stori_bundle_extract_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempExtract) }
        try FileManager.default.createDirectory(at: tempExtract, withIntermediateDirectories: true)

        try unzip(file: tempZip, to: tempExtract)

        // Expected layout: drum-kits/{kit_id}/..., soundfonts/*.sf2
        let drumKitsSource = tempExtract.appendingPathComponent("drum-kits")
        let soundFontsSource = tempExtract.appendingPathComponent("soundfonts")
        if FileManager.default.fileExists(atPath: drumKitsSource.path) {
            guard let kitsDir = Self.drumKitsDirectory else { throw AssetDownloadError.fileWriteFailed }
            try FileManager.default.createDirectory(at: kitsDir, withIntermediateDirectories: true)
            let contents = try FileManager.default.contentsOfDirectory(at: drumKitsSource, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            for item in contents {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let kitId = item.lastPathComponent
                let destKit = kitsDir.appendingPathComponent(kitId)
                if FileManager.default.fileExists(atPath: destKit.path) {
                    try FileManager.default.removeItem(at: destKit)
                }
                try FileManager.default.copyItem(at: item, to: destKit)
            }
        }
        if FileManager.default.fileExists(atPath: soundFontsSource.path) {
            guard let soundFontsDir = Self.soundFontsDirectory else { throw AssetDownloadError.fileWriteFailed }
            try FileManager.default.createDirectory(at: soundFontsDir, withIntermediateDirectories: true)
            let contents = try FileManager.default.contentsOfDirectory(at: soundFontsSource, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for item in contents where item.pathExtension.lowercased() == "sf2" {
                let dest = soundFontsDir.appendingPathComponent(item.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: item, to: dest)
            }
        }
    }

    /// Download all drum kits from the list (one zip per kit, sequential).
    /// Skips kits already installed. Progress: (current, total).
    func downloadAllDrumKits(progress: ((Int, Int) -> Void)? = nil) async throws {
        lastError = nil
        let kits = try await listDrumKits()
        let toDownload = kits.filter { !Self.isDrumKitInstalled(kitId: $0.id) }
        let total = toDownload.count
        guard total > 0 else { return }
        for (index, item) in toDownload.enumerated() {
            progress?(index + 1, total)
            try await downloadDrumKit(kitId: item.id)
        }
    }

    /// Download all soundfonts from the list (one file per soundfont, sequential).
    /// Skips soundfonts already installed. Progress: (current, total).
    func downloadAllSoundfonts(progress: ((Int, Int) -> Void)? = nil) async throws {
        lastError = nil
        let items = try await listSoundfonts()
        let toDownload = items.filter { !Self.isSoundFontInstalled(filename: $0.filename) }
        let total = toDownload.count
        guard total > 0 else { return }
        for (index, item) in toDownload.enumerated() {
            progress?(index + 1, total)
            try await downloadSoundFont(soundfontId: item.id, filename: item.filename)
        }
    }

    // MARK: - Helpers

    /// User-friendly message for connection failures; in DEBUG includes server URL so you can verify backend is running.
    private func connectionErrorMessage(for error: Error) -> String {
        let base = messageForConnectionError(error)
        #if DEBUG
        return base + " (server: \(baseURL))"
        #else
        return base
        #endif
    }

    /// User-friendly error message without exposing server URLs or technical details.
    private func userFriendlyErrorMessage(for error: Error) -> String {
        // Decoding errors
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .dataCorrupted, .keyNotFound, .typeMismatch, .valueNotFound:
                return "Invalid response from server. Please try again."
            @unknown default:
                return "Could not process server response. Please try again."
            }
        }
        // Use connection error message (already user-friendly, no server URL in production)
        return messageForConnectionError(error)
    }

    private func messageForConnectionError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost:
                return "Could not connect to the server. Check that the backend is running and the URL is correct."
            case .notConnectedToInternet:
                return "No internet connection."
            case .timedOut:
                return "Connection timed out. The server may be slow or unreachable."
            case .networkConnectionLost:
                return "Connection was lost."
            case .secureConnectionFailed:
                return "Secure connection failed. Check HTTPS and certificates."
            default:
                break
            }
        }
        let nsError = error as NSError
        if (nsError.domain == "AssetAPI" || nsError.domain == "AssetDownload"), (500...599).contains(nsError.code) {
            return "The server encountered an error (\(nsError.code)). Please try again later."
        }
        return error.localizedDescription
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200: break
        case 404:
            // Set user-friendly message without server URL
            lastError = "This pack is not available."
            throw AssetDownloadError.notFound
        case 503: throw AssetDownloadError.serviceUnavailable
        case 500...599:
            lastError = serverErrorMessage(statusCode: http.statusCode, data: data)
            throw AssetDownloadError.network(NSError(domain: "AssetAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
        default:
            // Don't expose raw response body to users; use generic message
            lastError = "Request failed (HTTP \(http.statusCode)). Please try again."
            throw AssetDownloadError.network(NSError(domain: "AssetAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
        }
    }

    /// User-facing message for 5xx server errors; optionally includes parsed detail from JSON body.
    private func serverErrorMessage(statusCode: Int, data: Data) -> String {
        var message = "The server encountered an error (\(statusCode)). Please try again later."
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let detail = (json["detail"] as? String) ?? (json["message"] as? String),
           !detail.isEmpty,
           detail.count < 200 {
            message = "Server error: \(detail)"
        } else if let body = String(data: data, encoding: .utf8), body.count < 150, !body.contains("<") {
            message = "Server error: \(body)"
        }
        #if DEBUG
        return message + " (server: \(baseURL))"
        #else
        return message
        #endif
    }

    private func downloadToFile(url: URL, destination: URL, progress: ((Double) -> Void)?) async throws {
        #if DEBUG
        print("🔵 [AssetDownload] Starting download from presigned URL (full): \(url.absoluteString)")
        #endif
        
        // Create a download delegate to track progress
        let delegate = DownloadDelegate(progressHandler: { [weak self] percent in
            Task { @MainActor in
                self?.downloadProgress = percent
                progress?(percent)
            }
        })
        
        let delegateSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        
        let task = delegateSession.downloadTask(with: url)
        task.resume()
        
        // Wait for completion
        let (tempURL, urlResponse) = try await withCheckedThrowingContinuation { continuation in
            delegate.completion = continuation
        }
        
        defer { 
            try? FileManager.default.removeItem(at: tempURL)
            delegateSession.finishTasksAndInvalidate()
        }
        
        if let http = urlResponse as? HTTPURLResponse, http.statusCode != 200 {
            #if DEBUG
            print("🔴 [AssetDownload] Download failed with HTTP \(http.statusCode)")
            if let headers = http.allHeaderFields as? [String: Any] {
                print("🔴 [AssetDownload] Response headers: \(headers)")
            }
            #endif
            switch http.statusCode {
            case 403:
                lastError = "Download permission denied. The download link may have expired or is invalid. Please try downloading again."
            case 404:
                lastError = "File not found. The asset may have been removed."
            case 500...599:
                lastError = serverErrorMessage(statusCode: http.statusCode, data: Data())
            default:
                lastError = "Download failed (HTTP \(http.statusCode)). Please try again."
            }
            throw AssetDownloadError.network(NSError(domain: "AssetDownload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        progress?(1.0)
        downloadProgress = 1.0
    }

    private func unzipKit(zipURL: URL, toKitDir: URL, kitId: String) throws {
        #if DEBUG
        print("🔵 [AssetDownload] Unzipping kit '\(kitId)'")
        print("   Zip: \(zipURL.path)")
        print("   Target: \(toKitDir.path)")
        #endif
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("stori_kit_\(kitId)_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try unzip(file: zipURL, to: tempDir)
        
        #if DEBUG
        print("🔵 [AssetDownload] Unzipped to temp: \(tempDir.path)")
        #endif
        
        // Zip may have top-level kit_id folder or flat kit.json + wavs
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        
        #if DEBUG
        print("🔵 [AssetDownload] Temp directory contents (\(contents.count) items):")
        for item in contents {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
            print("   - \(item.lastPathComponent) (isDir: \(isDir.boolValue))")
        }
        #endif
        
        // If zip has a single top-level folder (any name), copy its contents into toKitDir
        // so that kit.json ends up at toKitDir/kit.json for DrumKitLoader to find.
        if contents.count == 1,
           let single = contents.first,
           (try? single.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let inner = try FileManager.default.contentsOfDirectory(at: single, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            #if DEBUG
            print("🔵 [AssetDownload] Single top-level folder '\(single.lastPathComponent)', copying \(inner.count) items into kit dir")
            #endif
            for item in inner {
                let dest = toKitDir.appendingPathComponent(item.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
                try FileManager.default.copyItem(at: item, to: dest)
            }
        } else {
            // Flat zip: kit.json and wavs at root
            for item in contents {
                let dest = toKitDir.appendingPathComponent(item.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
                try FileManager.default.copyItem(at: item, to: dest)
            }
        }
        
        #if DEBUG
        let kitJson = toKitDir.appendingPathComponent("kit.json")
        print("🔵 [AssetDownload] After copy, kit.json exists: \(FileManager.default.fileExists(atPath: kitJson.path))")
        #endif
    }

    private func unzip(file zipURL: URL, to destDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destDir.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AssetDownloadError.unzipFailed
        }
    }

    // MARK: - Installed Check

    /// True if kit is installed at Application Support/Stori/DrumKits/{kitId}/ with kit.json
    static func isDrumKitInstalled(kitId: String) -> Bool {
        guard let kitsDir = drumKitsDirectory else { return false }
        let kitDir = kitsDir.appendingPathComponent(kitId)
        let kitJson = kitDir.appendingPathComponent("kit.json")
        return FileManager.default.fileExists(atPath: kitJson.path)
    }

    /// True if any drum kit folders exist on disk (even if old/broken format)
    static func hasAnyDrumKitsOnDisk() -> Bool {
        guard let kitsDir = drumKitsDirectory else { return false }
        guard FileManager.default.fileExists(atPath: kitsDir.path) else { return false }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: kitsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return false }
        return contents.contains { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// Remove all user-installed drum kits (clears Application Support/Stori/DrumKits).
    /// Use to clear old/broken kits before redownloading with the new format.
    static func removeAllDrumKits() throws {
        guard let kitsDir = drumKitsDirectory else { return }
        guard FileManager.default.fileExists(atPath: kitsDir.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(
            at: kitsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        for itemURL in contents {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue {
                try FileManager.default.removeItem(at: itemURL)
            }
        }
    }

    /// True if SoundFont file exists at Application Support/Stori/SoundFonts/{filename}
    static func isSoundFontInstalled(filename: String) -> Bool {
        guard let dir = soundFontsDirectory else { return false }
        let file = dir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: file.path)
    }
    
    // MARK: - Cleanup
}

// MARK: - Download Delegate for Progress Tracking

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void
    var completion: CheckedContinuation<(URL, URLResponse), Error>?
    
    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response else {
            completion?.resume(throwing: AssetDownloadError.network(NSError(domain: "AssetDownload", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
            return
        }
        
        // CRITICAL: URLSession deletes the temp file immediately after this method returns
        // We must move it to a persistent location NOW
        let persistentTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: persistentTemp)
            completion?.resume(returning: (persistentTemp, response))
        } catch {
            completion?.resume(throwing: error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let percent = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(percent)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completion?.resume(throwing: error)
        }
    }
}
