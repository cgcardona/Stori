//
//  MIDIImporter.swift
//  Stori
//
//  Imports standard MIDI files (.mid) and converts them to MIDIRegions
//

import Foundation
import AVFoundation
import CoreMIDI

class MIDIImporter {

    /// Maximum MIDI file size (10 MB) to prevent memory exhaustion.
    private static let maxFileSize: Int64 = 10_000_000

    /// Import a MIDI file and create MIDI regions
    static func importMIDIFile(from url: URL) -> Result<[MIDITrackData], MIDIImportError> {
        // Check file size before loading into memory
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? Int64,
              fileSize <= maxFileSize else {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64, size > maxFileSize {
                return .failure(.parseError("MIDI file too large (max \(maxFileSize / 1_000_000) MB)"))
            }
            return .failure(.fileReadError)
        }

        // Read MIDI file data
        guard let midiData = try? Data(contentsOf: url) else {
            return .failure(.fileReadError)
        }

        // Parse MIDI file
        do {
            let tracks = try parseMIDIFile(data: midiData)
            return .success(tracks)
        } catch {
            return .failure(.parseError(error.localizedDescription))
        }
    }
    
    // MARK: - MIDI File Parsing
    
    private static func parseMIDIFile(data: Data) throws -> [MIDITrackData] {
        var offset = 0
        
        // Read header chunk
        guard data.count >= 14 else {
            throw MIDIImportError.invalidFormat
        }
        
        // Check "MThd" signature
        let headerType = String(data: data[0..<4], encoding: .ascii)
        guard headerType == "MThd" else {
            throw MIDIImportError.invalidFormat
        }
        
        offset = 4
        
        // Header length (should be 6)
        let headerLength = data.readUInt32(at: offset)
        offset += 4
        
        guard headerLength == 6 else {
            throw MIDIImportError.invalidFormat
        }
        
        // Format type (0, 1, or 2)
        let format = data.readUInt16(at: offset)
        offset += 2
        
        // Number of tracks (cap to prevent abuse)
        let trackCount = data.readUInt16(at: offset)
        offset += 2
        let maxTracks = 500
        guard Int(trackCount) <= maxTracks else {
            throw MIDIImportError.invalidFormat
        }

        // Division (ticks per quarter note)
        let division = data.readUInt16(at: offset)
        offset += 2
        let ticksPerQuarterNote = division & 0x7FFF
        guard ticksPerQuarterNote > 0 else {
            throw MIDIImportError.invalidFormat
        }

        // Parse each track
        var tracks: [MIDITrackData] = []
        let maxTrackLength = 1_000_000 // 1 MB per track
        /// SECURITY (H-5): Max SysEx / meta payload size (64 KB).
        let maxPayloadLength = 65536

        for trackIndex in 0..<trackCount {
            guard offset + 8 <= data.count else { break }

            // Check "MTrk" signature
            let trackType = String(data: data[offset..<(offset + 4)], encoding: .ascii)
            guard trackType == "MTrk" else {
                throw MIDIImportError.invalidFormat
            }
            offset += 4

            // Track length with bounds validation
            let trackLength = Int(data.readUInt32(at: offset))
            offset += 4
            guard trackLength >= 0,
                  trackLength <= maxTrackLength,
                  offset + trackLength <= data.count else {
                throw MIDIImportError.invalidFormat
            }
            let trackEndOffset = offset + trackLength

            // Parse track events
            var notes: [MIDINote] = []
            let maxNotesPerTrack = 100_000
            var currentTick: UInt32 = 0
            var activeNotes: [UInt8: (tick: UInt32, velocity: UInt8)] = [:]
            var trackName = "MIDI Track \(trackIndex + 1)"
            var gmProgram: Int? = nil  // GM program number from Program Change event

            var runningStatus: UInt8 = 0

            while offset < trackEndOffset && offset < data.count {
                if notes.count >= maxNotesPerTrack {
                    break
                }
                // Read delta time (H-5: validate variable-length read bounds)
                guard offset < trackEndOffset else { break }
                let (deltaTime, bytesRead) = data.readVariableLength(at: offset)
                guard bytesRead >= 1, bytesRead <= 4, offset + bytesRead <= trackEndOffset else {
                    throw MIDIImportError.invalidFormat
                }
                offset += bytesRead
                currentTick += deltaTime
                
                guard offset < data.count, offset < trackEndOffset else { break }
                
                // Read event
                var status = data[offset]
                
                // Handle running status
                if status & 0x80 == 0 {
                    status = runningStatus
                } else {
                    offset += 1
                    runningStatus = status
                }
                
                let eventType = status & 0xF0
                
                switch eventType {
                case 0x80, 0x90: // Note Off / Note On
                    guard offset + 1 < data.count else { break }
                    let pitch = data[offset]
                    let velocity = data[offset + 1]
                    offset += 2
                    
                    if eventType == 0x90 && velocity > 0 {
                        // Note On
                        activeNotes[pitch] = (tick: currentTick, velocity: velocity)
                    } else {
                        // Note Off
                        if let noteOn = activeNotes[pitch] {
                            let duration = Double(currentTick - noteOn.tick) / Double(ticksPerQuarterNote)
                            let startTime = Double(noteOn.tick) / Double(ticksPerQuarterNote)
                            
                            let note = MIDINote(
                                pitch: pitch,
                                velocity: noteOn.velocity,
                                startTime: startTime,
                                duration: max(0.1, duration)
                            )
                            notes.append(note)
                            activeNotes.removeValue(forKey: pitch)
                        }
                    }
                    
                case 0xA0: // Polyphonic Key Pressure
                    offset += 2
                    
                case 0xB0: // Control Change
                    offset += 2
                    
                case 0xC0: // Program Change
                    guard offset < data.count else { break }
                    let program = data[offset]
                    offset += 1
                    // Store the first program change we encounter (primary instrument)
                    if gmProgram == nil {
                        gmProgram = Int(program)
                    }
                    
                case 0xD0: // Channel Pressure
                    offset += 1
                    
                case 0xE0: // Pitch Bend
                    offset += 2
                    
                case 0xF0: // System messages
                    if status == 0xFF {
                        // Meta event
                        guard offset < data.count else { break }
                        let metaType = data[offset]
                        offset += 1
                        
                        let (length, metaBytesRead) = data.readVariableLength(at: offset)
                        guard metaBytesRead >= 1, metaBytesRead <= 4, offset + metaBytesRead <= trackEndOffset else {
                            throw MIDIImportError.invalidFormat
                        }
                        offset += metaBytesRead
                        let lengthInt = Int(length)
                        guard lengthInt >= 0, lengthInt <= maxPayloadLength, offset + lengthInt <= data.count, offset + lengthInt <= trackEndOffset else {
                            throw MIDIImportError.invalidFormat
                        }
                        // Track name (meta 0x03)
                        if metaType == 0x03 && lengthInt <= 256 {
                            if let name = String(data: data[offset..<(offset + lengthInt)], encoding: .utf8) {
                                trackName = name
                            }
                        }
                        offset += lengthInt
                    } else if status == 0xF0 || status == 0xF7 {
                        // SysEx (H-5: cap payload size to prevent DoS)
                        let (length, sysexBytesRead) = data.readVariableLength(at: offset)
                        guard sysexBytesRead >= 1, sysexBytesRead <= 4, offset + sysexBytesRead <= trackEndOffset else {
                            throw MIDIImportError.invalidFormat
                        }
                        offset += sysexBytesRead
                        let lengthInt = Int(length)
                        guard lengthInt >= 0, lengthInt <= maxPayloadLength, offset + lengthInt <= data.count, offset + lengthInt <= trackEndOffset else {
                            throw MIDIImportError.invalidFormat
                        }
                        offset += lengthInt
                    }
                    
                default:
                    break
                }
            }
            
            // Close any remaining active notes
            for (pitch, noteOn) in activeNotes {
                let duration = Double(currentTick - noteOn.tick) / Double(ticksPerQuarterNote)
                let startTime = Double(noteOn.tick) / Double(ticksPerQuarterNote)
                
                let note = MIDINote(
                    pitch: pitch,
                    velocity: noteOn.velocity,
                    startTime: startTime,
                    duration: max(0.1, duration)
                )
                notes.append(note)
            }
            
            if !notes.isEmpty {
                let trackData = MIDITrackData(name: trackName, notes: notes, gmProgram: gmProgram)
                tracks.append(trackData)
                
                #if DEBUG
                if let program = gmProgram {
                    print("🎹 [MIDI Import] Track '\(trackName)': \(notes.count) notes, GM Program \(program)")
                } else {
                    print("🎹 [MIDI Import] Track '\(trackName)': \(notes.count) notes, no program change")
                }
                #endif
            }
            
            offset = trackEndOffset
        }
        
        return tracks
    }
}

// MARK: - Supporting Types

struct MIDITrackData {
    let name: String
    let notes: [MIDINote]
    /// GM program number (0-127) from Program Change event, if present in the MIDI file
    let gmProgram: Int?
}

enum MIDIImportError: Error {
    case fileReadError
    case invalidFormat
    case parseError(String)
    
    var localizedDescription: String {
        switch self {
        case .fileReadError:
            return "Could not read MIDI file"
        case .invalidFormat:
            return "Invalid MIDI file format"
        case .parseError(let details):
            return "Parse error: \(details)"
        }
    }
}

// MARK: - Data Reading Extensions

extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }
    
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        return (UInt32(self[offset]) << 24) |
               (UInt32(self[offset + 1]) << 16) |
               (UInt32(self[offset + 2]) << 8) |
               UInt32(self[offset + 3])
    }
    
    /// SECURITY (H-5): VLQ parser with overflow and sanity-cap to prevent DoS/crash from malformed MIDI.
    func readVariableLength(at offset: Int) -> (value: UInt32, bytesRead: Int) {
        var value: UInt32 = 0
        var bytesRead = 0
        var currentOffset = offset
        /// Max reasonable VLQ for MIDI delta time (~74 hours at 960 PPQN, 120 BPM)
        let maxReasonable: UInt32 = 0x0FFFFFFF

        while currentOffset < count && bytesRead < 4 {
            let byte = self[currentOffset]

            // Overflow check before shifting
            let shifted = value << 7
            guard shifted >> 7 == value else {
                return (0, bytesRead)
            }
            value = shifted | UInt32(byte & 0x7F)

            if value > maxReasonable {
                return (0, bytesRead)
            }

            bytesRead += 1
            currentOffset += 1

            if byte & 0x80 == 0 {
                break
            }
        }

        return (value, bytesRead)
    }
}

