// MARK: - FileNameSanitizer

import Foundation

/// Sanitize a string for safe use as a filename.
/// SECURITY: Prevents path traversal, null byte injection, control characters, and other attacks.
/// Use for project names, export filenames, and any user-controlled filename segment.
func sanitizeFileName(_ name: String) -> String {
    var sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)

    // SECURITY: Unicode normalization to prevent look-alike attacks and filesystem inconsistencies
    // NFC (precomposed) for consistent cross-platform behavior
    sanitized = sanitized.precomposedStringWithCanonicalMapping

    // SECURITY: Remove null bytes (path truncation attack)
    sanitized = sanitized.replacingOccurrences(of: "\0", with: "")

    // SECURITY: Remove ALL control characters (0x00-0x1F, 0x7F) that can corrupt filenames
    sanitized = sanitized.filter { char in
        guard let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value
        return value >= 0x20 && value != 0x7F
    }

    // SECURITY: Remove path traversal sequences (before replacing invalid chars)
    sanitized = sanitized.replacingOccurrences(of: "..", with: "")
    sanitized = sanitized.replacingOccurrences(of: "./", with: "")
    sanitized = sanitized.replacingOccurrences(of: ".\\", with: "")

    // Remove or replace characters that aren't safe for file names
    let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    sanitized = sanitized.components(separatedBy: invalidChars).joined(separator: "_")

    // Remove leading/trailing dots and underscores (hidden files on Unix, Windows compatibility)
    sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "._"))

    // SECURITY: Check for reserved Windows filenames (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
    let reservedNames = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5",
                         "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4",
                         "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
    if reservedNames.contains(sanitized.uppercased()) {
        sanitized = "_\(sanitized)"
    }

    if sanitized.isEmpty {
        sanitized = "Untitled"
    }

    // SECURITY: Limit filename length (macOS 255 bytes; leave room for extension/timestamp)
    if sanitized.count > 200 {
        sanitized = String(sanitized.prefix(200))
    }

    return sanitized
}
