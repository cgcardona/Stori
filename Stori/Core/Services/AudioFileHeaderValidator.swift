//
//  AudioFileHeaderValidator.swift
//  Stori
//
//  SECURITY (H-1): Validates audio file magic bytes before passing to AVAudioFile.
//  Reduces risk of decoder bugs and metadata injection from malformed or crafted files.
//

import Foundation

// MARK: - Audio File Header Validator

enum AudioFileHeaderValidator {

    /// Validate that the file at the given URL has a recognized audio format header.
    /// Call this before AVAudioFile(forReading: url) to reject unknown/malformed files.
    /// - Parameter url: File URL to validate
    /// - Returns: true if header matches WAV, AIFF, FLAC, MP3, or M4A/MP4; false otherwise
    static func validateHeader(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 12), header.count >= 4 else {
            return false
        }

        let magic = header.prefix(4)

        // WAV: RIFF....WAVE
        if magic == Data([0x52, 0x49, 0x46, 0x46]) {
            guard header.count >= 12,
                  header[8..<12] == Data([0x57, 0x41, 0x56, 0x45]) else {
                return false
            }
            return true
        }

        // AIFF / AIFC: FORM....AIFF or FORM....AIFC
        if magic == Data([0x46, 0x4F, 0x52, 0x4D]) {
            guard header.count >= 12 else { return false }
            let form = header[8..<12]
            return form == Data([0x41, 0x49, 0x46, 0x46]) || form == Data([0x41, 0x49, 0x46, 0x43])
        }

        // FLAC: fLaC
        if magic == Data([0x66, 0x4C, 0x61, 0x43]) {
            return true
        }

        // MP3: ID3 at start, or frame sync 0xFF 0xFB / 0xFF 0xFA / 0xFF 0xF3
        if magic.prefix(3) == Data([0x49, 0x44, 0x33]) {
            return true
        }
        if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
            return true
        }

        // M4A / MP4: ....ftyp (at offset 4)
        if header.count >= 8 {
            let ftyp = header[4..<8]
            if ftyp == Data([0x66, 0x74, 0x79, 0x70]) {
                return true
            }
        }

        return false
    }
}
