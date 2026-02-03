//
//  AudioModelsTests.swift
//  StoriTests
//
//  Unit tests for AudioModels.swift - Core audio data models
//

import XCTest
@testable import Stori

final class AudioModelsTests: XCTestCase {
    
    // MARK: - TrackType Tests
    
    func testTrackTypeRawValues() {
        XCTAssertEqual(TrackType.audio.rawValue, "audio")
        XCTAssertEqual(TrackType.midi.rawValue, "midi")
        XCTAssertEqual(TrackType.instrument.rawValue, "instrument")
        XCTAssertEqual(TrackType.bus.rawValue, "bus")
    }
    
    func testTrackTypeCodable() {
        assertCodableRoundTrip(TrackType.audio)
        assertCodableRoundTrip(TrackType.midi)
        assertCodableRoundTrip(TrackType.instrument)
        assertCodableRoundTrip(TrackType.bus)
    }
    
    // MARK: - TrackColor Tests
    
    func testTrackColorHexValues() {
        XCTAssertEqual(TrackColor.blue.rawValue, "#3B82F6")
        XCTAssertEqual(TrackColor.red.rawValue, "#EF4444")
        XCTAssertEqual(TrackColor.green.rawValue, "#10B981")
    }
    
    func testTrackColorCustom() {
        let customColor = TrackColor.custom("#FF00FF")
        XCTAssertEqual(customColor.rawValue, "#FF00FF")
    }
    
    func testTrackColorCodable() {
        assertCodableRoundTrip(TrackColor.blue)
        assertCodableRoundTrip(TrackColor.custom("#AABBCC"))
    }
    
    func testAllPredefinedCases() {
        XCTAssertEqual(TrackColor.allPredefinedCases.count, 10)
        XCTAssertTrue(TrackColor.allPredefinedCases.contains(.blue))
        XCTAssertTrue(TrackColor.allPredefinedCases.contains(.red))
    }
    
    // MARK: - TimeSignature Tests
    
    func testTimeSignatureDefaults() {
        XCTAssertEqual(TimeSignature.fourFour.numerator, 4)
        XCTAssertEqual(TimeSignature.fourFour.denominator, 4)
        XCTAssertEqual(TimeSignature.threeFour.numerator, 3)
        XCTAssertEqual(TimeSignature.threeFour.denominator, 4)
    }
    
    func testTimeSignatureDisplayString() {
        let timeSig = TimeSignature(numerator: 6, denominator: 8)
        XCTAssertEqual(timeSig.displayString, "6/8")
    }
    
    func testTimeSignatureCodable() {
        assertCodableRoundTrip(TimeSignature.fourFour)
        assertCodableRoundTrip(TimeSignature(numerator: 7, denominator: 8))
    }
    
    // MARK: - BeatPosition Tests
    
    func testBeatPositionInitialization() {
        let position = BeatPosition(4.5)
        XCTAssertEqual(position.beats, 4.5)
    }
    
    func testBeatPositionNonNegative() {
        let position = BeatPosition(-5.0)
        XCTAssertEqual(position.beats, 0.0, "BeatPosition should clamp negative values to 0")
    }
    
    func testBeatPositionZero() {
        XCTAssertEqual(BeatPosition.zero.beats, 0.0)
    }
    
    func testBeatPositionToSeconds() {
        let position = BeatPosition(4.0)  // 4 beats
        
        // At 120 BPM: 4 beats = 2 seconds
        assertApproximatelyEqual(position.toSeconds(tempo: 120.0), 2.0)
        
        // At 60 BPM: 4 beats = 4 seconds
        assertApproximatelyEqual(position.toSeconds(tempo: 60.0), 4.0)
        
        // At 180 BPM: 4 beats = 1.33... seconds
        assertApproximatelyEqual(position.toSeconds(tempo: 180.0), 4.0 / 3.0)
    }
    
    func testBeatPositionFromSeconds() {
        // At 120 BPM: 2 seconds = 4 beats
        let position = BeatPosition.fromSeconds(2.0, tempo: 120.0)
        assertApproximatelyEqual(position.beats, 4.0)
    }
    
    func testBeatPositionBar() {
        let position = BeatPosition(9.0)  // 9 beats in 4/4 = bar 3
        XCTAssertEqual(position.bar(timeSignature: .fourFour), 3)
        
        // In 3/4 beat: 9 beats = bar 4
        XCTAssertEqual(position.bar(timeSignature: .threeFour), 4)
    }
    
    func testBeatPositionBeatInBar() {
        let position = BeatPosition(5.0)  // Beat 5 in 4/4 = beat 2 of bar 2
        XCTAssertEqual(position.beatInBar(timeSignature: .fourFour), 2)
    }
    
    func testBeatPositionSubdivision() {
        let position = BeatPosition(1.25)
        XCTAssertEqual(position.subdivision, 25)
        
        let position2 = BeatPosition(3.75)
        XCTAssertEqual(position2.subdivision, 75)
    }
    
    func testBeatPositionTick() {
        let position = BeatPosition(1.5)  // Half a beat after beat 1
        XCTAssertEqual(position.tick(ppqn: 480), 240)
    }
    
    func testBeatPositionArithmetic() {
        let pos1 = BeatPosition(4.0)
        let pos2 = BeatPosition(2.0)
        
        XCTAssertEqual((pos1 + pos2).beats, 6.0)
        XCTAssertEqual((pos1 - pos2).beats, 2.0)
        XCTAssertEqual((pos1 + 3.0).beats, 7.0)
        XCTAssertEqual((pos1 * 2.0).beats, 8.0)
        XCTAssertEqual((pos1 / 2.0).beats, 2.0)
    }
    
    func testBeatPositionComparison() {
        let pos1 = BeatPosition(4.0)
        let pos2 = BeatPosition(6.0)
        
        XCTAssertTrue(pos1 < pos2)
        XCTAssertFalse(pos2 < pos1)
        XCTAssertEqual(pos1, BeatPosition(4.0))
    }
    
    func testBeatPositionDisplayString() {
        let position = BeatPosition(5.25)  // Bar 2, beat 2, subdivision 25
        XCTAssertEqual(position.displayString(timeSignature: .fourFour), "2.2.25")
    }
    
    func testBeatPositionCodable() {
        assertCodableRoundTrip(BeatPosition(4.5))
        assertCodableRoundTrip(BeatPosition.zero)
    }
    
    // MARK: - ProjectUIState Tests
    
    func testProjectUIStateDefaults() {
        let state = ProjectUIState.default
        
        XCTAssertEqual(state.horizontalZoom, 0.8)
        XCTAssertEqual(state.verticalZoom, 1.0)
        XCTAssertTrue(state.snapToGrid)
        XCTAssertTrue(state.catchPlayheadEnabled)
        XCTAssertFalse(state.metronomeEnabled)
        XCTAssertFalse(state.showingInspector)  // Default is now false until service is available
        XCTAssertFalse(state.showingMixer)
    }
    
    func testProjectUIStateCodable() {
        var state = ProjectUIState()
        state.horizontalZoom = 1.5
        state.showingMixer = true
        state.metronomeEnabled = true
        
        assertCodableRoundTrip(state)
    }
    
    // MARK: - AudioProject Tests
    
    func testAudioProjectInitialization() {
        let project = AudioProject(name: "My Project", tempo: 140.0)
        
        XCTAssertEqual(project.name, "My Project")
        XCTAssertEqual(project.tempo, 140.0)
        XCTAssertEqual(project.keySignature, "C")
        XCTAssertEqual(project.timeSignature, .fourFour)
        XCTAssertEqual(project.sampleRate, 48000.0)
        XCTAssertEqual(project.bufferSize, 512)
        XCTAssertTrue(project.tracks.isEmpty)
        XCTAssertTrue(project.buses.isEmpty)
        XCTAssertEqual(project.version, AudioProject.currentVersion)
    }
    
    func testAudioProjectDefaultValues() {
        let project = AudioProject(name: "Default Project")
        
        XCTAssertEqual(project.tempo, 120.0)
        XCTAssertEqual(project.keySignature, "C")
    }
    
    func testAudioProjectAddTrack() {
        var project = AudioProject(name: "Test")
        let track = AudioTrack(name: "Track 1")
        
        project.addTrack(track)
        
        XCTAssertEqual(project.tracks.count, 1)
        XCTAssertEqual(project.tracks.first?.name, "Track 1")
        XCTAssertEqual(project.trackCount, 1)
    }
    
    func testAudioProjectRemoveTrack() {
        var project = AudioProject(name: "Test")
        let track = AudioTrack(name: "Track 1")
        project.addTrack(track)
        
        project.removeTrack(withId: track.id)
        
        XCTAssertTrue(project.tracks.isEmpty)
    }
    
    func testAudioProjectDuration() {
        var project = AudioProject(name: "Test")
        XCTAssertEqual(project.durationBeats, 0)
        
        // Add track with content
        var track = AudioTrack(name: "Track 1", trackType: .midi)
        var region = MIDIRegion(startBeat: 0, durationBeats: 8.0)
        region.addNote(MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0))
        track.midiRegions.append(region)
        project.addTrack(track)
        
        XCTAssertEqual(project.durationBeats, 8.0)
    }
    
    func testAudioProjectCodable() {
        var project = AudioProject(name: "Test Project", tempo: 128.0)
        project.keySignature = "G"
        
        let track = AudioTrack(name: "My Track", trackType: .midi, color: .purple)
        project.addTrack(track)
        
        assertCodableRoundTrip(project)
    }
    
    func testAudioProjectModifiedAtUpdates() {
        var project = AudioProject(name: "Test")
        let originalModified = project.modifiedAt
        
        // Small delay to ensure time difference
        Thread.sleep(forTimeInterval: 0.01)
        
        project.addTrack(AudioTrack(name: "New Track"))
        
        XCTAssertGreaterThan(project.modifiedAt, originalModified)
    }
    
    // MARK: - AudioTrack Tests
    
    func testAudioTrackInitialization() {
        let track = AudioTrack(name: "My Track", trackType: .audio, color: .red)
        
        XCTAssertEqual(track.name, "My Track")
        XCTAssertEqual(track.trackType, .audio)
        XCTAssertEqual(track.color, .red)
        XCTAssertTrue(track.isEnabled)
        XCTAssertFalse(track.isFrozen)
        XCTAssertTrue(track.regions.isEmpty)
        XCTAssertTrue(track.midiRegions.isEmpty)
    }
    
    func testAudioTrackTypeHelpers() {
        let audioTrack = AudioTrack(name: "Audio", trackType: .audio)
        let midiTrack = AudioTrack(name: "MIDI", trackType: .midi)
        let instrumentTrack = AudioTrack(name: "Instrument", trackType: .instrument)
        
        XCTAssertTrue(audioTrack.isAudioTrack)
        XCTAssertFalse(audioTrack.isMIDITrack)
        
        XCTAssertFalse(midiTrack.isAudioTrack)
        XCTAssertTrue(midiTrack.isMIDITrack)
        
        XCTAssertTrue(instrumentTrack.isMIDITrack)
    }
    
    func testAudioTrackIcons() {
        XCTAssertEqual(AudioTrack(name: "Audio", trackType: .audio).trackTypeIcon, "waveform")
        XCTAssertEqual(AudioTrack(name: "MIDI", trackType: .midi).trackTypeIcon, "pianokeys")
        XCTAssertEqual(AudioTrack(name: "Instrument", trackType: .instrument).trackTypeIcon, "pianokeys.inverse")
        XCTAssertEqual(AudioTrack(name: "Bus", trackType: .bus).trackTypeIcon, "arrow.triangle.branch")
    }
    
    func testAudioTrackContentChecks() {
        var track = AudioTrack(name: "Test", trackType: .midi)
        
        XCTAssertFalse(track.hasContent)
        XCTAssertFalse(track.hasMIDI)
        XCTAssertFalse(track.hasAudio)
        
        let region = MIDIRegion(name: "Region 1")
        track.addMIDIRegion(region)
        
        XCTAssertTrue(track.hasContent)
        XCTAssertTrue(track.hasMIDI)
    }
    
    func testAudioTrackAddRemoveMIDIRegion() {
        var track = AudioTrack(name: "Test", trackType: .midi)
        let region = MIDIRegion(name: "Test Region")
        
        track.addMIDIRegion(region)
        XCTAssertEqual(track.midiRegions.count, 1)
        
        track.removeMIDIRegion(withId: region.id)
        XCTAssertTrue(track.midiRegions.isEmpty)
    }
    
    func testAudioTrackAutomation() {
        let track = AudioTrack(name: "Test")
        
        // Default automation lane should exist
        XCTAssertEqual(track.automationLanes.count, 1)
        XCTAssertEqual(track.automationLanes.first?.parameter, .volume)
        XCTAssertEqual(track.automationMode, .read)
        XCTAssertFalse(track.automationExpanded)
        XCTAssertFalse(track.hasAutomationData)
    }
    
    func testAudioTrackCodable() {
        var track = AudioTrack(name: "Test Track", trackType: .instrument, color: .orange)
        track.mixerSettings.volume = 0.5
        track.mixerSettings.pan = 0.75
        
        assertCodableRoundTrip(track)
    }
    
    // MARK: - MixerSettings Tests
    
    func testMixerSettingsDefaults() {
        let settings = MixerSettings()
        
        XCTAssertEqual(settings.volume, 0.8)
        XCTAssertEqual(settings.pan, 0.5)  // Center
        XCTAssertEqual(settings.highEQ, 0.0)
        XCTAssertEqual(settings.midEQ, 0.0)
        XCTAssertEqual(settings.lowEQ, 0.0)
        XCTAssertFalse(settings.isMuted)
        XCTAssertFalse(settings.isSolo)
        XCTAssertTrue(settings.eqEnabled)
        XCTAssertFalse(settings.phaseInverted)
    }
    
    func testMixerSettingsCodable() {
        var settings = MixerSettings()
        settings.volume = 0.6
        settings.isMuted = true
        settings.phaseInverted = true
        
        assertCodableRoundTrip(settings)
    }
    
    // MARK: - TransportState Tests
    
    func testTransportStateIsPlaying() {
        XCTAssertFalse(TransportState.stopped.isPlaying)
        XCTAssertTrue(TransportState.playing.isPlaying)
        XCTAssertTrue(TransportState.recording.isPlaying)
        XCTAssertFalse(TransportState.paused.isPlaying)
    }
    
    // MARK: - MixerBus Tests
    // NOTE: EffectType tests removed - type was deprecated and removed from codebase
    
    func testMixerBusInitialization() {
        let bus = MixerBus(name: "Reverb Bus")
        
        XCTAssertEqual(bus.name, "Reverb Bus")
        XCTAssertEqual(bus.inputLevel, 0.0)
        XCTAssertEqual(bus.outputLevel, 0.75)
        XCTAssertFalse(bus.isMuted)
        XCTAssertFalse(bus.isSolo)
    }
    
    func testMixerBusCodable() {
        let bus = MixerBus(name: "Test Bus", inputLevel: 0.5, outputLevel: 0.8)
        assertCodableRoundTrip(bus)
    }
    
    // MARK: - TrackSend Tests
    
    func testTrackSendInitialization() {
        let busId = UUID()
        let send = TrackSend(busId: busId, sendLevel: 0.5, isPreFader: true)
        
        XCTAssertEqual(send.busId, busId)
        XCTAssertEqual(send.sendLevel, 0.5)
        XCTAssertTrue(send.isPreFader)
        XCTAssertEqual(send.pan, 0.0)
        XCTAssertFalse(send.isMuted)
    }
    
    // MARK: - TrackGroup Tests
    
    func testTrackGroupInitialization() {
        let group = TrackGroup(name: "Drums")
        
        XCTAssertEqual(group.name, "Drums")
        XCTAssertTrue(group.isEnabled)
        XCTAssertTrue(group.linkedParameters.contains(.volume))
        XCTAssertTrue(group.linkedParameters.contains(.mute))
        XCTAssertTrue(group.linkedParameters.contains(.solo))
    }
    
    func testTrackGroupCodable() {
        let group = TrackGroup(name: "Strings", linkedParameters: [.volume, .pan])
        assertCodableRoundTrip(group)
    }
    
    // MARK: - I/O Routing Tests
    
    func testTrackInputSourceDisplayNames() {
        XCTAssertEqual(TrackInputSource.none.displayName, "No Input")
        XCTAssertEqual(TrackInputSource.systemDefault.displayName, "System Input")
        XCTAssertEqual(TrackInputSource.input(channel: 1).displayName, "Input 1")
        XCTAssertEqual(TrackInputSource.stereoInput(left: 1, right: 2).displayName, "Input 1/2")
    }
    
    func testTrackOutputDestinationDisplayNames() {
        XCTAssertEqual(TrackOutputDestination.stereoOut.displayName, "Stereo Out")
        XCTAssertEqual(TrackOutputDestination.output(channel: 3).displayName, "Output 3")
    }
    
    // MARK: - Performance Tests
    
    func testProjectCreationPerformance() {
        measure {
            for _ in 0..<100 {
                _ = AudioProject(name: "Performance Test")
            }
        }
    }
    
    func testTrackCreationPerformance() {
        measure {
            for i in 0..<100 {
                _ = AudioTrack(name: "Track \(i)")
            }
        }
    }
}
