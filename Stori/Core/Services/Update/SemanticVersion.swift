//
//  SemanticVersion.swift
//  Stori
//
//  Semantic version parser and comparator supporting major.minor.patch[-prerelease].
//  Follows SemVer 2.0 rules: prerelease versions have lower precedence than the
//  associated normal version.
//

import Foundation

// MARK: - SemanticVersion

/// A parsed semantic version (major.minor.patch with optional prerelease label).
///
/// Supports formats like `0.2.3`, `v0.2.3`, `1.0.0-beta.1`, `0.2.3-rc.2`.
/// Prerelease versions sort lower than the same version without a prerelease tag.
struct SemanticVersion: Equatable, Hashable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    
    /// Optional prerelease label, e.g. "beta.1", "rc.2", "alpha"
    let prerelease: String?
    
    /// The raw string this version was parsed from (normalized, without leading "v")
    let raw: String
    
    // MARK: - Initialization
    
    init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        
        var s = "\(major).\(minor).\(patch)"
        if let pre = prerelease, !pre.isEmpty {
            s += "-\(pre)"
        }
        self.raw = s
    }
    
    // MARK: - Parsing
    
    /// Parse a version string. Returns nil if the format is invalid.
    ///
    /// Accepted formats: `0.2.3`, `v0.2.3`, `0.2.3-beta.1`, `v1.0.0-rc.2`
    static func parse(_ string: String) -> SemanticVersion? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip leading "v" or "V"
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s = String(s.dropFirst())
        }
        
        guard !s.isEmpty else { return nil }
        
        // Split on "-" to separate prerelease
        let dashParts = s.split(separator: "-", maxSplits: 1)
        guard !dashParts.isEmpty else { return nil }
        let versionPart = String(dashParts[0])
        let prereleasePart: String? = dashParts.count > 1 ? String(dashParts[1]) : nil
        
        // Parse major.minor.patch
        let components = versionPart.split(separator: ".")
        guard components.count >= 2 else { return nil }
        
        guard let major = Int(components[0]),
              let minor = Int(components[1]) else {
            return nil
        }
        
        let patch: Int
        if components.count >= 3 {
            guard let p = Int(components[2]) else { return nil }
            patch = p
        } else {
            patch = 0
        }
        
        return SemanticVersion(
            major: major,
            minor: minor,
            patch: patch,
            prerelease: prereleasePart
        )
    }
    
    // MARK: - Properties
    
    /// Whether this is a prerelease version
    var isPrerelease: Bool {
        prerelease != nil && !(prerelease?.isEmpty ?? true)
    }
    
    /// Display string with "v" prefix
    var displayString: String {
        "v\(raw)"
    }
    
    // MARK: - Comparison Helpers
    
    /// The "distance" from self to `other` in terms of major/minor/patch gaps.
    /// Returns positive values when `other` is ahead of `self`.
    func distance(to other: SemanticVersion) -> VersionDistance {
        VersionDistance(
            majorDelta: other.major - major,
            minorDelta: other.minor - minor,
            patchDelta: other.patch - patch
        )
    }
}

// MARK: - Comparable

extension SemanticVersion: Comparable {
    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        // Compare major
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        // Compare minor
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        // Compare patch
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        
        // SemVer rule: prerelease < release
        // e.g. 1.0.0-alpha < 1.0.0
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false // equal
        case (.some, nil):
            return true  // prerelease < release
        case (nil, .some):
            return false // release > prerelease
        case (.some(let l), .some(let r)):
            return comparePrerelease(l, r)
        }
    }
    
    /// Compare prerelease identifiers per SemVer 2.0 spec:
    /// Split by ".", compare each identifier: numeric < numeric, alpha < alpha, numeric < alpha
    private static func comparePrerelease(_ lhs: String, _ rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".")
        let rhsParts = rhs.split(separator: ".")
        
        for i in 0..<max(lhsParts.count, rhsParts.count) {
            // Fewer identifiers = lower precedence (if all preceding are equal)
            guard i < lhsParts.count else { return true }
            guard i < rhsParts.count else { return false }
            
            let l = String(lhsParts[i])
            let r = String(rhsParts[i])
            
            if l == r { continue }
            
            let lNum = Int(l)
            let rNum = Int(r)
            
            switch (lNum, rNum) {
            case (.some(let ln), .some(let rn)):
                return ln < rn
            case (.some, nil):
                return true  // numeric < alpha
            case (nil, .some):
                return false // alpha > numeric
            case (nil, nil):
                return l < r // lexicographic
            }
        }
        
        return false // equal
    }
}

// MARK: - Codable

extension SemanticVersion: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let parsed = SemanticVersion.parse(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid semantic version: \(string)"
            )
        }
        self = parsed
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

// MARK: - VersionDistance

/// Describes how far apart two versions are
struct VersionDistance: Equatable, Sendable {
    let majorDelta: Int
    let minorDelta: Int
    let patchDelta: Int
    
    /// Whether a major version jump is involved
    var isMajorBehind: Bool { majorDelta > 0 }
    
    /// Whether at least a minor version jump is involved
    var isMinorBehind: Bool { majorDelta > 0 || minorDelta > 0 }
    
    /// Human-readable summary
    var summary: String {
        if majorDelta > 0 {
            return "\(majorDelta) major version\(majorDelta > 1 ? "s" : "") behind"
        } else if minorDelta > 0 {
            return "\(minorDelta) minor version\(minorDelta > 1 ? "s" : "") behind"
        } else if patchDelta > 0 {
            return "\(patchDelta) patch\(patchDelta > 1 ? "es" : "") behind"
        } else {
            return "up to date"
        }
    }
}
