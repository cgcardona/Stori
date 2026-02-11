//
//  AppConfig.swift
//  Stori
//
//  Centralized configuration loaded from environment variables or Config.plist (gitignored).
//

import Foundation

/// Application configuration and environment settings
enum AppConfig {
    
    // MARK: - API Configuration
    
    /// Base URL for Stori backend API (no trailing slash).
    /// Sources: STORI_API_URL env, then Config.plist (gitignored). Real URLs only in env or Config.plist.
    static var apiBaseURL: String {
        if let envURL = ProcessInfo.processInfo.environment["STORI_API_URL"], !envURL.isEmpty {
            return envURL
        }
        if let url = loadConfigPlistValue(key: "ApiBaseURL") {
            return url
        }
        #if DEBUG
        return "https://stage.example.com"
        #else
        return ""
        #endif
    }

    /// Load value from Config.plist (gitignored; not committed)
    private static func loadConfigPlistValue(key: String) -> String? {
        guard let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let configDict = NSDictionary(contentsOfFile: configPath) as? [String: Any],
              let value = configDict[key] as? String, !value.isEmpty else {
            return nil
        }
        return value
    }
    
    /// Validate that API URLs use HTTPS in production
    static func validateSecureConnection() {
        let url = apiBaseURL
        
        #if !DEBUG
        guard url.hasPrefix("https://") else {
            fatalError("❌ SECURITY: Production builds must use HTTPS (got: \(url))")
        }
        #endif
        
        // Warn in DEBUG if using HTTP for non-localhost
        #if DEBUG
        if url.hasPrefix("http://") && !url.contains("localhost") && !url.contains("127.0.0.1") {
        }
        #endif
    }
    
    // MARK: - Network Configuration
    
    /// Default request timeout for standard API calls
    static let defaultTimeout: TimeInterval = 30
    
    /// Extended timeout for long-running operations (generation, export, etc.)
    static let extendedTimeout: TimeInterval = 300
    
    /// Short timeout for health checks and quick validation
    static let healthCheckTimeout: TimeInterval = 5
    
    // MARK: - Feature Flags
    
    /// Whether Composer features are enabled
    static let composerEnabled: Bool = false  // Disabled for initial open source release
    
    /// Whether wallet features are enabled
    static let walletEnabled: Bool = false  // Disabled for initial open source release
    
    /// Whether marketplace features are enabled
    static let marketplaceEnabled: Bool = false  // Disabled for initial open source release
    
    // MARK: - Build Information
    
    /// Check if running in DEBUG mode
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
