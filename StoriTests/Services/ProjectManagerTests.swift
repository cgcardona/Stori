//
//  ProjectManagerTests.swift
//  StoriTests
//
//  Unit tests for ProjectManager - Core project management service
//

import XCTest
@testable import Stori

final class ProjectManagerTests: XCTestCase {
    
    // MARK: - Project Creation Tests
    
    func testCreateProjectWithDefaultSettings() {
        let project = AudioProject(name: "My Project")
        
        XCTAssertEqual(project.name, "My Project")
        XCTAssertEqual(project.tempo, 120.0)
        XCTAssertEqual(project.keySignature, "C")
        XCTAssertEqual(project.timeSignature.numerator, 4)
        XCTAssertEqual(project.timeSignature.denominator, 4)
        XCTAssertEqual(project.sampleRate, 48000.0)
        XCTAssertEqual(project.bufferSize, 512)
        XCTAssertTrue(project.tracks.isEmpty)
        XCTAssertTrue(project.buses.isEmpty)
    }
    
    func testCreateProjectWithCustomSettings() {
        let project = AudioProject(
            name: "Custom Project",
            tempo: 140.0,
            keySignature: "G",
            timeSignature: TimeSignature(numerator: 3, denominator: 4),
            sampleRate: 96000.0,
            bufferSize: 256
        )
        
        XCTAssertEqual(project.name, "Custom Project")
        XCTAssertEqual(project.tempo, 140.0)
        XCTAssertEqual(project.keySignature, "G")
        XCTAssertEqual(project.timeSignature.numerator, 3)
        XCTAssertEqual(project.sampleRate, 96000.0)
        XCTAssertEqual(project.bufferSize, 256)
    }
    
    func testProjectHasUniqueId() {
        let project1 = AudioProject(name: "Project 1")
        let project2 = AudioProject(name: "Project 2")
        
        XCTAssertNotEqual(project1.id, project2.id)
    }
    
    func testProjectHasValidTimestamps() {
        let beforeCreation = Date()
        let project = AudioProject(name: "Test")
        let afterCreation = Date()
        
        XCTAssertGreaterThanOrEqual(project.createdAt, beforeCreation)
        XCTAssertLessThanOrEqual(project.createdAt, afterCreation)
        XCTAssertEqual(project.createdAt, project.modifiedAt)
    }
    
    // MARK: - Track Management Tests
    
    func testAddTrackToProject() {
        var project = AudioProject(name: "Test")
        let track = AudioTrack(name: "Track 1", trackType: .audio)
        
        project.addTrack(track)
        
        XCTAssertEqual(project.trackCount, 1)
        XCTAssertEqual(project.tracks.first?.name, "Track 1")
    }
    
    func testAddMultipleTracks() {
        var project = AudioProject(name: "Test")
        
        project.addTrack(AudioTrack(name: "Audio 1", trackType: .audio))
        project.addTrack(AudioTrack(name: "MIDI 1", trackType: .midi))
        project.addTrack(AudioTrack(name: "Instrument 1", trackType: .instrument))
        
        XCTAssertEqual(project.trackCount, 3)
        XCTAssertEqual(project.tracks[0].trackType, .audio)
        XCTAssertEqual(project.tracks[1].trackType, .midi)
        XCTAssertEqual(project.tracks[2].trackType, .instrument)
    }
    
    func testRemoveTrackFromProject() {
        var project = AudioProject(name: "Test")
        let track1 = AudioTrack(name: "Track 1")
        let track2 = AudioTrack(name: "Track 2")
        
        project.addTrack(track1)
        project.addTrack(track2)
        XCTAssertEqual(project.trackCount, 2)
        
        project.removeTrack(withId: track1.id)
        
        XCTAssertEqual(project.trackCount, 1)
        XCTAssertEqual(project.tracks.first?.name, "Track 2")
    }
    
    func testRemoveNonexistentTrack() {
        var project = AudioProject(name: "Test")
        project.addTrack(AudioTrack(name: "Track 1"))
        
        let fakeId = UUID()
        project.removeTrack(withId: fakeId)
        
        XCTAssertEqual(project.trackCount, 1, "Should not affect tracks when removing nonexistent ID")
    }
    
    func testAddTrackUpdatesModifiedAt() {
        var project = AudioProject(name: "Test")
        let originalModified = project.modifiedAt
        
        Thread.sleep(forTimeInterval: 0.01)
        
        project.addTrack(AudioTrack(name: "New Track"))
        
        XCTAssertGreaterThan(project.modifiedAt, originalModified)
    }
    
    // MARK: - Bus Management Tests
    
    func testCreateBus() {
        let bus = MixerBus(name: "Reverb Bus")
        
        XCTAssertEqual(bus.name, "Reverb Bus")
        XCTAssertEqual(bus.inputLevel, 0.0)
        XCTAssertEqual(bus.outputLevel, 0.75)
        XCTAssertFalse(bus.isMuted)
        XCTAssertFalse(bus.isSolo)
    }
    
    func testAddBusToProject() {
        var project = AudioProject(name: "Test")
        let bus = MixerBus(name: "FX Bus")
        
        project.buses.append(bus)
        
        XCTAssertEqual(project.buses.count, 1)
        XCTAssertEqual(project.buses.first?.name, "FX Bus")
    }
    
    // MARK: - Project Duration Tests
    
    func testEmptyProjectDuration() {
        let project = AudioProject(name: "Empty")
        XCTAssertEqual(project.durationBeats, 0)
    }
    
    func testProjectDurationWithMIDIContent() {
        var project = AudioProject(name: "Test")
        var track = AudioTrack(name: "MIDI", trackType: .midi)
        
        var region = MIDIRegion(startTime: 0, duration: 8.0)
        region.addNote(MIDINote(pitch: 60, startTime: 0, duration: 1.0))
        track.midiRegions.append(region)
        
        var region2 = MIDIRegion(startTime: 8.0, duration: 4.0)
        region2.addNote(MIDINote(pitch: 62, startTime: 0, duration: 1.0))
        track.midiRegions.append(region2)
        
        project.addTrack(track)
        
        XCTAssertEqual(project.durationBeats, 12.0)
    }
    
    func testProjectDurationWithMultipleTracks() {
        var project = AudioProject(name: "Test")
        
        // Track 1: 8 beats
        var track1 = AudioTrack(name: "Track 1", trackType: .midi)
        var region1 = MIDIRegion(startTime: 0, duration: 8.0)
        region1.addNote(MIDINote(pitch: 60, startTime: 0, duration: 1.0))
        track1.midiRegions.append(region1)
        
        // Track 2: 16 beats
        var track2 = AudioTrack(name: "Track 2", trackType: .midi)
        var region2 = MIDIRegion(startTime: 0, duration: 16.0)
        region2.addNote(MIDINote(pitch: 62, startTime: 0, duration: 1.0))
        track2.midiRegions.append(region2)
        
        project.addTrack(track1)
        project.addTrack(track2)
        
        XCTAssertEqual(project.durationBeats, 16.0, "Should use longest track duration")
    }
    
    // MARK: - UI State Tests
    
    func testProjectUIStateDefaults() {
        let project = AudioProject(name: "Test")
        
        XCTAssertEqual(project.uiState.horizontalZoom, 0.8)
        XCTAssertTrue(project.uiState.snapToGrid)
        XCTAssertTrue(project.uiState.catchPlayheadEnabled)
        XCTAssertFalse(project.uiState.metronomeEnabled)
        XCTAssertTrue(project.uiState.showingInspector)
        XCTAssertFalse(project.uiState.showingMixer)
    }
    
    func testProjectUIStatePersistence() {
        var project = AudioProject(name: "Test")
        project.uiState.showingMixer = true
        project.uiState.horizontalZoom = 2.0
        project.uiState.metronomeEnabled = true
        
        // Encode and decode
        assertCodableRoundTrip(project)
    }
    
    // MARK: - Codable Tests
    
    func testProjectCodableRoundTrip() {
        var project = AudioProject(name: "Complex Project", tempo: 128.0)
        project.keySignature = "Bb"
        
        // Add tracks
        var track1 = AudioTrack(name: "Lead", trackType: .instrument, color: .purple)
        track1.mixerSettings.volume = 0.9
        track1.mixerSettings.pan = 0.3
        
        var track2 = AudioTrack(name: "Bass", trackType: .midi, color: .blue)
        var region = MIDIRegion(name: "Bass Pattern", startTime: 0, duration: 8.0)
        region.addNote(MIDINote(pitch: 36, velocity: 100, startTime: 0, duration: 1.0))
        track2.midiRegions.append(region)
        
        project.addTrack(track1)
        project.addTrack(track2)
        
        // Add bus
        project.buses.append(MixerBus(name: "Reverb", outputLevel: 0.5))
        
        assertCodableRoundTrip(project)
    }
    
    func testProjectVersioning() {
        let project = AudioProject(name: "Test")
        XCTAssertEqual(project.version, AudioProject.currentVersion)
    }
    
    // MARK: - Track Group Tests
    
    func testTrackGroupCreation() {
        let group = TrackGroup(name: "Drums", linkedParameters: [.volume, .mute])
        
        XCTAssertEqual(group.name, "Drums")
        XCTAssertTrue(group.isEnabled)
        XCTAssertTrue(group.linkedParameters.contains(.volume))
        XCTAssertTrue(group.linkedParameters.contains(.mute))
        XCTAssertFalse(group.linkedParameters.contains(.solo))
    }
    
    func testTrackGroupCodable() {
        let group = TrackGroup(name: "Strings")
        assertCodableRoundTrip(group)
    }
    
    // MARK: - Performance Tests
    
    func testCreateManyTracksPerformance() {
        measure {
            var project = AudioProject(name: "Large Project")
            for i in 0..<100 {
                project.addTrack(AudioTrack(name: "Track \(i)"))
            }
            XCTAssertEqual(project.trackCount, 100)
        }
    }
    
    func testProjectSerializationPerformance() {
        var project = AudioProject(name: "Performance Test")
        
        // Create 50 tracks with MIDI content
        for i in 0..<50 {
            var track = AudioTrack(name: "Track \(i)", trackType: .midi)
            var region = MIDIRegion(startTime: 0, duration: 16.0)
            
            // Add 32 notes per region
            for j in 0..<32 {
                region.addNote(MIDINote(
                    pitch: UInt8(48 + (j % 24)),
                    velocity: UInt8(80 + (j % 40)),
                    startTime: Double(j) * 0.5,
                    duration: 0.4
                ))
            }
            
            track.midiRegions.append(region)
            project.addTrack(track)
        }
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        measure {
            do {
                let data = try encoder.encode(project)
                _ = try decoder.decode(AudioProject.self, from: data)
            } catch {
                XCTFail("Serialization failed: \(error)")
            }
        }
    }
}
