//
//  PromptSanitizer.swift
//  Stori
//
//  Sanitizes user-supplied text before inclusion in AI prompts to reduce prompt injection risk.
//  M-1: Unicode normalization, homoglyph detection, and regex-based injection pattern removal.
//

import Foundation

enum PromptSanitizer {

    /// Maximum total prompt length (chars).
    static let maxPromptLength = 2000

    /// Maximum length for a single user-supplied field (e.g. specific details).
    static let maxFieldLength = 500

    /// Sanitizes user-supplied text before inclusion in AI prompts.
    /// - Parameter input: Raw user input (e.g. from TextField).
    /// - Returns: Sanitized string safe to concatenate into prompts.
    /// M-1: Adds Unicode normalization and stronger injection pattern removal.
    static func sanitize(_ input: String) -> String {
        var cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping

        // M-1: Strip suspicious Unicode (homoglyphs, control chars) to reduce bypass attacks
        if containsSuspiciousUnicode(cleaned) {
            cleaned = stripToSafeASCII(cleaned)
        }

        // Remove injection patterns (literal, case-insensitive)
        let literalPatterns = [
            "ignore previous instructions",
            "ignore all previous",
            "disregard the above",
            "disregard all prior",
            "forget everything",
            "system:",
            "assistant:",
            "user:",
            "instruction:",
            "new instruction:",
            "override:",
            "```"
        ]
        for pattern in literalPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }

        // M-1: Regex-based removal for word-boundary patterns
        let regexPatterns = [
            "\\bignore\\s+(?:previous|prior|all)\\s+(?:instructions?|directions?)\\b",
            "\\bdisregard\\s+(?:the\\s+)?(?:above|previous)\\b",
            "\\bforget\\s+everything\\b",
            "\\bnew\\s+(?:instruction|directive|command)\\b"
        ]
        for pattern in regexPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Collapse multiple spaces/newlines
        cleaned = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if cleaned.count > maxFieldLength {
            cleaned = String(cleaned.prefix(maxFieldLength))
        }

        return cleaned
    }

    /// M-1: Detect suspicious Unicode (homoglyphs, control chars) that may bypass literal checks.
    private static func containsSuspiciousUnicode(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Cyrillic (looks like Latin)
            if (0x0400...0x04FF).contains(scalar.value) { return true }
            // Greek
            if (0x0370...0x03FF).contains(scalar.value) { return true }
            // General punctuation / invisible
            if (0x2000...0x206F).contains(scalar.value) { return true }
            // Control characters
            if scalar.value < 32 && scalar.value != 9 && scalar.value != 10 && scalar.value != 13 { return true }
        }
        return false
    }

    /// M-1: Keep only ASCII letters, digits, common punctuation.
    private static func stripToSafeASCII(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            (scalar.value >= 32 && scalar.value < 127) || scalar.value == 9 || scalar.value == 10 || scalar.value == 13
        })
    }

    /// Truncates a full prompt to max length. Call after building the prompt.
    static func truncatePrompt(_ prompt: String) -> String {
        if prompt.count <= maxPromptLength {
            return prompt
        }
        return String(prompt.prefix(maxPromptLength))
    }
}
