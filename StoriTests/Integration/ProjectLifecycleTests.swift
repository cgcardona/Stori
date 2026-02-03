//
//  ProjectLifecycleTests.swift
//  StoriTests
//
//  Integration tests for complete project workflows
//

import XCTest
@testable import Stori

final class ProjectLifecycleTests: XCTestCase {
    
    // MARK: - Project Creation Workflow
    
    func testCompleteProjectCreation() {
        // Create new project
        var project = AudioProject(name: "Integration Test", tempo: 128.0)
        project.keySignature = "G"
        
        // Add audio track
        var audioTrack = AudioTrack(name: "Lead Guitar", trackType: .audio, color: .orange)
        audioTrack.mixerSettings.volume = 0.85
        audioTrack.mixerSettings.pan = 0.3
        project.addTrack(audioTrack)
        
        // Add MIDI track with content
        var midiTrack = AudioTrack(name: "Piano", trackType: .instrument, color: .purple)
        var region = MIDIRegion(name: "Intro", startBeat: 0, durationBeats: 8.0)
        
        // Add chord progression
        let chord = [60, 64, 67]  // C Major
        for note in chord {
            region.addNote(MIDINote(
                pitch: UInt8(note),
                velocity: 80,
                startBeat: 0,
                durationBeats: 4.0
            ))
        }
        
        midiTrack.midiRegions.append(region)
        project.addTrack(midiTrack)
        
        // Add bus for effects
        let reverbBus = MixerBus(name: "Reverb", outputLevel: 0.4)
        project.buses.append(reverbBus)
        
        // Verify project state
        XCTAssertEqual(project.name, "Integration Test")
        XCTAssertEqual(project.tempo, 128.0)
        XCTAssertEqual(project.keySignature, "G")
        XCTAssertEqual(project.trackCount, 2)
        XCTAssertEqual(project.buses.count, 1)
        XCTAssertEqual(project.durationBeats, 8.0)
    }
    
    // MARK: - Serialization Roundtrip
    
    func testProjectSerializationRoundtrip() {
        // Create complex project
        var project = createComplexProject()
        let originalTrackCount = project.trackCount
        let originalTempo = project.tempo
        let originalName = project.name
        
        // Serialize
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(project) else {
            XCTFail("Failed to encode project")
            return
        }
        
        // Verify JSON is valid and reasonable size
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertLessThan(data.count, 10_000_000)  // Sanity check
        
        // Deserialize
        let decoder = JSONDecoder()
        guard let loadedProject = try? decoder.decode(AudioProject.self, from: data) else {
            XCTFail("Failed to decode project")
            return
        }
        
        // Verify all data matches
        XCTAssertEqual(loadedProject.name, originalName)
        XCTAssertEqual(loadedProject.tempo, originalTempo)
        XCTAssertEqual(loadedProject.trackCount, originalTrackCount)
        XCTAssertEqual(loadedProject.tracks[0].name, project.tracks[0].name)
        XCTAssertEqual(loadedProject.tracks[0].mixerSettings.volume, project.tracks[0].mixerSettings.volume)
    }
    
    func testProjectWithMIDIContentRoundtrip() {
        var project = AudioProject(name: "MIDI Test")
        
        // Create track with detailed MIDI content
        var track = AudioTrack(name: "Lead", trackType: .midi)
        var region = MIDIRegion(name: "Melody", startBeat: 0, durationBeats: 16.0)
        
        // Add melody with varying velocities
        let melody = [(60, 100), (62, 90), (64, 110), (65, 85), (67, 95)]
        for (i, (pitch, velocity)) in melody.enumerated() {
            region.addNote(MIDINote(
                pitch: UInt8(pitch),
                velocity: UInt8(velocity),
                startBeat: TimeInterval(i),
                durationBeats: 0.8
            ))
        }
        
        // Add CC automation
        region.controllerEvents.append(MIDICCEvent(controller: 1, value: 64, beat: 0))
        region.controllerEvents.append(MIDICCEvent(controller: 1, value: 100, beat: 4.0))
        
        track.midiRegions.append(region)
        project.addTrack(track)
        
        // Roundtrip
        assertCodableRoundTrip(project)
    }
    
    func testProjectWithAutomationRoundtrip() {
        var project = AudioProject(name: "Automation Test")
        
        var track = AudioTrack(name: "Synth", trackType: .instrument)
        
        // Add volume automation
        var volumeLane = AutomationLane(parameter: .volume)
        volumeLane.addPoint(atBeat: 0, value: 0.0, curve: .smooth)
        volumeLane.addPoint(atBeat: 4.0, value: 1.0, curve: .linear)
        volumeLane.addPoint(atBeat: 8.0, value: 0.7, curve: .exponential)
        
        track.automationLanes.append(volumeLane)
        track.automationMode = .read
        track.automationExpanded = true
        
        project.addTrack(track)
        
        // Roundtrip
        assertCodableRoundTrip(project)
    }
    
    // MARK: - Track Management Workflow
    
    func testTrackOrderManagement() {
        var project = AudioProject(name: "Track Order Test")
        
        let track1 = AudioTrack(name: "Track 1")
        let track2 = AudioTrack(name: "Track 2")
        let track3 = AudioTrack(name: "Track 3")
        
        project.addTrack(track1)
        project.addTrack(track2)
        project.addTrack(track3)
        
        XCTAssertEqual(project.tracks[0].name, "Track 1")
        XCTAssertEqual(project.tracks[1].name, "Track 2")
        XCTAssertEqual(project.tracks[2].name, "Track 3")
        
        // Remove middle track
        project.removeTrack(withId: track2.id)
        
        XCTAssertEqual(project.trackCount, 2)
        XCTAssertEqual(project.tracks[0].name, "Track 1")
        XCTAssertEqual(project.tracks[1].name, "Track 3")
    }
    
    func testTrackDuplication() {
        var project = AudioProject(name: "Duplicate Test")
        
        // Create track with content
        var originalTrack = AudioTrack(name: "Original", trackType: .midi, color: .purple)
        originalTrack.mixerSettings.volume = 0.75
        originalTrack.mixerSettings.pan = -0.3
        
        var region = MIDIRegion(name: "Pattern")
        region.addNote(MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0))
        region.addNote(MIDINote(pitch: 64, startBeat: 1.0, durationBeats: 1.0))
        originalTrack.midiRegions.append(region)
        
        project.addTrack(originalTrack)
        
        // Simulate duplication by creating a copy
        var duplicatedTrack = originalTrack
        duplicatedTrack = AudioTrack(
            id: UUID(),  // New ID
            name: "Original Copy",
            trackType: originalTrack.trackType,
            color: originalTrack.color
        )
        duplicatedTrack.mixerSettings = originalTrack.mixerSettings
        duplicatedTrack.midiRegions = originalTrack.midiRegions.map { region in
            var newRegion = region
            // Create new IDs for notes in duplicated region
            return newRegion
        }
        
        project.addTrack(duplicatedTrack)
        
        XCTAssertEqual(project.trackCount, 2)
        XCTAssertNotEqual(project.tracks[0].id, project.tracks[1].id)
    }
    
    // MARK: - Region Editing Workflow
    
    func testMIDIRegionEditing() {
        var region = MIDIRegion(name: "Editable Region", durationBeats: 8.0)
        
        // Add initial notes
        region.addNote(MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0))
        region.addNote(MIDINote(pitch: 62, startBeat: 1.0, durationBeats: 1.0))
        region.addNote(MIDINote(pitch: 64, startBeat: 2.0, durationBeats: 1.0))
        
        XCTAssertEqual(region.noteCount, 3)
        
        // Transpose all notes
        region.transpose(by: 5)
        
        XCTAssertEqual(region.notes[0].pitch, 65)
        XCTAssertEqual(region.notes[1].pitch, 67)
        XCTAssertEqual(region.notes[2].pitch, 69)
        
        // Shift in time
        region.shift(by: 4.0)
        
        assertApproximatelyEqual(region.notes[0].startBeat, 4.0)
        assertApproximatelyEqual(region.notes[1].startBeat, 5.0)
        assertApproximatelyEqual(region.notes[2].startBeat, 6.0)
    }
    
    func testRegionQuantization() {
        let resolution = SnapResolution.eighth
        
        let unquantizedTimes = [0.12, 0.48, 0.51, 0.87, 1.23]
        let expectedQuantized = [0.0, 0.5, 0.5, 1.0, 1.0]
        
        for (i, time) in unquantizedTimes.enumerated() {
            let quantized = resolution.quantize(beat: time)
            assertApproximatelyEqual(quantized, expectedQuantized[i])
        }
    }
    
    func testRegionQuantizationWithStrength() {
        let resolution = SnapResolution.quarter
        
        // 50% quantize strength
        let original = 0.7
        let quantized = resolution.quantize(beat: original, strength: 0.5)
        
        // Should be halfway between 0.7 and 1.0
        assertApproximatelyEqual(quantized, 0.85)
    }
    
    // MARK: - Mixer Workflow
    
    func testMixerSettingsWorkflow() {
        var track = AudioTrack(name: "Mix Test")
        
        // Set initial levels
        track.mixerSettings.volume = 0.8
        track.mixerSettings.pan = 0.0  // Center
        track.mixerSettings.eqEnabled = true
        
        // Add EQ adjustments
        track.mixerSettings.lowEQ = -3.0
        track.mixerSettings.midEQ = 2.0
        track.mixerSettings.highEQ = -1.0
        
        // Solo the track
        track.mixerSettings.isSolo = true
        
        // Verify state
        XCTAssertEqual(track.mixerSettings.volume, 0.8)
        XCTAssertTrue(track.mixerSettings.isSolo)
        XCTAssertEqual(track.mixerSettings.lowEQ, -3.0)
    }
    
    func testBusSendWorkflow() {
        var project = AudioProject(name: "Bus Test")
        
        // Create reverb bus
        let reverbBus = MixerBus(name: "Reverb", outputLevel: 0.6)
        project.buses.append(reverbBus)
        
        // Create track with send
        var track = AudioTrack(name: "Vocal")
        let send = TrackSend(busId: reverbBus.id, sendLevel: 0.4, isPreFader: false)
        track.sends.append(send)
        
        project.addTrack(track)
        
        XCTAssertEqual(project.tracks[0].sends.count, 1)
        XCTAssertEqual(project.tracks[0].sends[0].busId, reverbBus.id)
    }
    
    // MARK: - Automation Workflow
    
    func testAutomationRecordingSimulation() {
        var lane = AutomationLane(parameter: .volume)
        
        // Simulate recording automation data over time
        let recordedData: [(beat: Double, value: Float)] = [
            (0.0, 0.5),
            (1.0, 0.6),
            (2.0, 0.8),
            (3.0, 0.7),
            (4.0, 0.9),
            (5.0, 0.85),
            (6.0, 0.75),
            (7.0, 0.65),
            (8.0, 0.5)
        ]
        
        for data in recordedData {
            lane.addPoint(atBeat: data.beat, value: data.value)
        }
        
        XCTAssertEqual(lane.points.count, 9)
        
        // Verify playback values
        assertApproximatelyEqual(lane.value(atBeat: 0), 0.5)
        assertApproximatelyEqual(lane.value(atBeat: 4.0), 0.9)
        assertApproximatelyEqual(lane.value(atBeat: 8.0), 0.5)
    }
    
    // MARK: - UI State Persistence
    
    func testUIStatePreservation() {
        var project = AudioProject(name: "UI State Test")
        
        // Configure UI state
        project.uiState.horizontalZoom = 1.5
        project.uiState.showingMixer = true
        project.uiState.showingPianoRoll = true
        project.uiState.metronomeEnabled = true
        project.uiState.metronomeVolume = 0.5
        project.uiState.inspectorWidth = 350
        project.uiState.mixerHeight = 400
        
        // Roundtrip
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        guard let data = try? encoder.encode(project),
              let loaded = try? decoder.decode(AudioProject.self, from: data) else {
            XCTFail("Serialization failed")
            return
        }
        
        XCTAssertEqual(loaded.uiState.horizontalZoom, 1.5)
        XCTAssertTrue(loaded.uiState.showingMixer)
        XCTAssertTrue(loaded.uiState.showingPianoRoll)
        XCTAssertTrue(loaded.uiState.metronomeEnabled)
        XCTAssertEqual(loaded.uiState.metronomeVolume, 0.5)
        XCTAssertEqual(loaded.uiState.inspectorWidth, 350)
    }
    
    // MARK: - Track Group Workflow
    
    func testTrackGrouping() {
        var project = AudioProject(name: "Group Test")
        
        // Create track group
        let drumGroup = TrackGroup(name: "Drums", linkedParameters: [.volume, .mute, .solo])
        project.groups.append(drumGroup)
        
        // Create drum tracks
        var kickTrack = AudioTrack(name: "Kick", trackType: .audio)
        kickTrack.groupId = drumGroup.id
        
        var snareTrack = AudioTrack(name: "Snare", trackType: .audio)
        snareTrack.groupId = drumGroup.id
        
        var hatTrack = AudioTrack(name: "Hi-Hat", trackType: .audio)
        hatTrack.groupId = drumGroup.id
        
        project.addTrack(kickTrack)
        project.addTrack(snareTrack)
        project.addTrack(hatTrack)
        
        // Verify grouping
        let groupedTracks = project.tracks.filter { $0.groupId == drumGroup.id }
        XCTAssertEqual(groupedTracks.count, 3)
    }
    
    // MARK: - Performance Tests
    
    func testLargeProjectHandling() {
        measure {
            var project = AudioProject(name: "Large Project")
            
            // Create 100 tracks with content
            for i in 0..<100 {
                var track = AudioTrack(name: "Track \(i)", trackType: .midi)
                
                var region = MIDIRegion(name: "Region \(i)", durationBeats: 32.0)
                
                // Add 64 notes per region
                for j in 0..<64 {
                    region.addNote(MIDINote(
                        pitch: UInt8(48 + (j % 24)),
                        velocity: UInt8(80 + (j % 40)),
                        startBeat: Double(j) * 0.5,
                        durationBeats: 0.4
                    ))
                }
                
                track.midiRegions.append(region)
                project.addTrack(track)
            }
            
            XCTAssertEqual(project.trackCount, 100)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createComplexProject() -> AudioProject {
        var project = AudioProject(name: "Complex Project", tempo: 140.0)
        project.keySignature = "D"
        project.timeSignature = TimeSignature(numerator: 4, denominator: 4)
        
        // Audio track
        var audioTrack = AudioTrack(name: "Guitar", trackType: .audio, color: .orange)
        audioTrack.mixerSettings.volume = 0.9
        audioTrack.mixerSettings.pan = 0.2
        project.addTrack(audioTrack)
        
        // MIDI track with content
        var midiTrack = AudioTrack(name: "Piano", trackType: .instrument, color: .purple)
        var region = MIDIRegion(name: "Intro", startBeat: 0, durationBeats: 16.0)
        for i in 0..<8 {
            region.addNote(MIDINote(
                pitch: UInt8(60 + i),
                velocity: 80,
                startBeat: Double(i) * 2,
                durationBeats: 1.5
            ))
        }
        midiTrack.midiRegions.append(region)
        project.addTrack(midiTrack)
        
        // Bus
        project.buses.append(MixerBus(name: "Reverb", outputLevel: 0.4))
        
        // UI State
        project.uiState.showingMixer = true
        project.uiState.horizontalZoom = 1.2
        
        return project
    }
}
